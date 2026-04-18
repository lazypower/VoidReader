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

    /// Creates a file watcher for the given URL.
    /// - Parameters:
    ///   - url: The file URL to watch
    ///   - callback: Called on the main queue when the file is modified externally
    public init?(url: URL, callback: @escaping () -> Void) {
        guard url.isFileURL else { return nil }
        self.url = url
        self.resolvedTargetPath = url.resolvingSymlinksInPath().path
        self.callback = callback

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
                    DispatchQueue.main.async {
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
    public func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
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
