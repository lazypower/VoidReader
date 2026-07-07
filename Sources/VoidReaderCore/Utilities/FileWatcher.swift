import Foundation
import CoreServices

/// Watches a single file for external modifications using FSEventStream.
///
/// FSEventStream watches a directory path, not a file descriptor, so it survives
/// atomic saves (write-to-temp + rename) that invalidate file-descriptor-based
/// watchers like `DispatchSourceFileSystemObject`.
public final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let url: URL
    private let resolvedTargetPath: String
    private let callback: () -> Void
    private let queue = DispatchQueue(label: "place.wabash.VoidReader.FileWatcher")
    /// Marks `queue` so `stop()` can detect when it is already executing there
    /// (a callback that dropped the last reference and triggered deinit) and
    /// avoid deadlocking on `queue.sync`.
    private static let queueKey = DispatchSpecificKey<Void>()

    /// Set once `stop()` runs. Read on the main thread by the escaped callback
    /// hop to suppress a user callback whose event was delivered before stop().
    private let stateLock = NSLock()
    private var stopped = false
    private var isStopped: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return stopped
    }

    /// Creates a file watcher for the given URL.
    ///
    /// Threading contract: this is a main-thread-owned object. `callback` fires
    /// on the main queue, and `stop()` is expected to be called on the main
    /// thread (the app owns it as SwiftUI `@State`). Under that contract the
    /// stopped-flag check and the callback fire are serialized on the main queue,
    /// so a callback never runs after `stop()` returns. Calling `stop()` from a
    /// background thread reopens a narrow check-then-fire window where one final
    /// callback could still land; don't do that.
    /// - Parameters:
    ///   - url: The file URL to watch
    ///   - callback: Called on the main queue when the file is modified externally
    public init?(url: URL, callback: @escaping () -> Void) {
        guard url.isFileURL else { return nil }
        self.url = url
        self.resolvedTargetPath = url.resolvingSymlinksInPath().path
        self.callback = callback

        queue.setSpecific(key: Self.queueKey, value: ())
        guard startStream() else { return nil }
    }

    deinit {
        stop()
    }

    private func startStream() -> Bool {
        // Watch the parent directory of the RESOLVED target so symlinks work and
        // so we survive atomic rename-over saves into the real file's directory.
        let parentPath = URL(fileURLWithPath: resolvedTargetPath).deletingLastPathComponent().path
        let pathsToWatch = [parentPath] as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let cCallback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
            guard let info = clientCallBackInfo else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

            let target = watcher.resolvedTargetPath
            let targetName = watcher.url.lastPathComponent

            for i in 0..<numEvents {
                guard i < paths.count else { break }
                let eventPath = paths[i]

                // Match either exact resolved path or filename (covers atomic rename cases
                // where FSEvents may report the temp path that was renamed to our target).
                let resolved = URL(fileURLWithPath: eventPath).resolvingSymlinksInPath().path
                if resolved == target || URL(fileURLWithPath: eventPath).lastPathComponent == targetName {
                    // Hop to main WEAKLY: the synchronous body is serialized with
                    // teardown on `queue`, but this escaped block is not. A strong
                    // capture would defer deinit and let the callback fire after
                    // stop()/dealloc; a weak capture plus the `stopped` gate makes
                    // teardown fail closed — the block no-ops if the watcher was
                    // stopped or freed in the meantime.
                    DispatchQueue.main.async { [weak watcher] in
                        guard let watcher, !watcher.isStopped else { return }
                        watcher.callback()
                    }
                    return
                }
            }
        }

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            cCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1, // latency seconds
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            return false
        }

        FSEventStreamSetDispatchQueue(newStream, queue)
        FSEventStreamStart(newStream)
        self.stream = newStream
        return true
    }

    /// Stops watching the file.
    ///
    /// Teardown runs on the stream's own dispatch queue so it serializes with
    /// in-flight FSEvents callbacks — otherwise a callback already dequeued on
    /// that queue could dereference `self` after `deinit` released it (the
    /// context is `passUnretained`). The `queueKey` check covers the reentrant
    /// case where the last reference is dropped inside a callback, so `deinit`
    /// runs on `queue` itself and a blocking `queue.sync` would deadlock.
    public func stop() {
        // Mark stopped first so any already-enqueued main-thread callback hop
        // no-ops, even if the stream teardown below is a no-op (already nil).
        stateLock.lock(); stopped = true; stateLock.unlock()

        let teardown = {
            if let stream = self.stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
        }

        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            teardown()
        } else {
            queue.sync(execute: teardown)
        }
    }
}

// MARK: - File Modification Date

public extension URL {
    /// Returns the file's modification date, or nil if unavailable.
    var fileModificationDate: Date? {
        try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
