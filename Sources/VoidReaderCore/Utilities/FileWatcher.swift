import Foundation

/// Watches a file for external modifications using DispatchSource.
public final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let fileDescriptor: Int32
    private let callback: () -> Void

    /// Creates a file watcher for the given URL.
    /// - Parameters:
    ///   - url: The file URL to watch
    ///   - callback: Called when the file is modified externally
    public init?(url: URL, callback: @escaping () -> Void) {
        guard url.isFileURL else { return nil }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }

        self.fileDescriptor = fd
        self.callback = callback

        startWatching()
    }

    deinit {
        stop()
    }

    private func startWatching() {
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.callback()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor {
                close(fd)
            }
        }

        source.resume()
        self.source = source
    }

    /// Stops watching the file.
    public func stop() {
        source?.cancel()
        source = nil
    }
}

// MARK: - File Modification Date

public extension URL {
    /// Returns the file's modification date, or nil if unavailable.
    var fileModificationDate: Date? {
        try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
