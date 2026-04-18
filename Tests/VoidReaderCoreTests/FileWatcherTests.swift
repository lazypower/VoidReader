import Testing
import Foundation
@testable import VoidReaderCore

/// Tests for FileWatcher's behavioral contract.
///
/// The primary regression guard is atomic-rename saves (write-to-temp + rename-over),
/// which is how most editors (VS Code, vim with writebackup, `mv`, etc.) save files.
/// A file-descriptor-based watcher dies after the first such save because the fd points
/// to the original inode, which is now unlinked. FSEventStream watches paths, not fds,
/// so it keeps working.
@Suite("File Watcher Tests")
struct FileWatcherTests {

    // MARK: - Helpers

    private static func makeTempFile(contents: String = "initial") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voidreader-filewatcher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("doc.md")
        try contents.write(to: url, atomically: false, encoding: .utf8)
        return url
    }

    private static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// Simulates an atomic-rename save (the pattern VS Code, vim, etc. use).
    private static func atomicRenameSave(contents: String, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".tmp-\(UUID().uuidString)")
        try contents.write(to: tempURL, atomically: false, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    /// Waits up to `timeout` seconds for `predicate` to become true, polling every 50ms.
    private static func waitUntil(timeout: TimeInterval, _ predicate: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return predicate()
    }

    /// Thread-safe fire counter for the watcher callback.
    private final class FireCounter: @unchecked Sendable {
        private var _count = 0
        private let lock = NSLock()
        func increment() { lock.lock(); _count += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    }

    // MARK: - Tests

    @Test("Fires on direct in-place write")
    func firesOnDirectWrite() async throws {
        let url = try Self.makeTempFile(contents: "v1")
        defer { Self.cleanup(url) }

        let counter = FireCounter()
        let watcher = FileWatcher(url: url) { counter.increment() }
        #expect(watcher != nil)

        // Give the stream a moment to arm
        try await Task.sleep(nanoseconds: 300_000_000)

        try "v2".write(to: url, atomically: false, encoding: .utf8)

        let fired = await Self.waitUntil(timeout: 3.0) { counter.count >= 1 }
        #expect(fired, "Watcher should fire on direct write")

        watcher?.stop()
    }

    @Test("Fires repeatedly across atomic rename saves (regression: fd-based watcher died after first)")
    func firesAcrossAtomicRenames() async throws {
        let url = try Self.makeTempFile(contents: "v1")
        defer { Self.cleanup(url) }

        let counter = FireCounter()
        let watcher = FileWatcher(url: url) { counter.increment() }
        #expect(watcher != nil)

        try await Task.sleep(nanoseconds: 300_000_000)

        // Three atomic-rename saves, spaced wider than the FSEvents latency (100ms)
        // so the events don't coalesce into a single batch.
        try Self.atomicRenameSave(contents: "v2", to: url)
        _ = await Self.waitUntil(timeout: 2.0) { counter.count >= 1 }

        try Self.atomicRenameSave(contents: "v3", to: url)
        _ = await Self.waitUntil(timeout: 2.0) { counter.count >= 2 }

        try Self.atomicRenameSave(contents: "v4", to: url)
        let gotThree = await Self.waitUntil(timeout: 2.0) { counter.count >= 3 }

        #expect(gotThree, "Watcher should fire on every atomic rename, not just the first. Actual fires: \(counter.count)")

        watcher?.stop()
    }

    @Test("Fires on mv/rm+recreate (delete then new file with same name)")
    func firesOnDeleteAndRecreate() async throws {
        let url = try Self.makeTempFile(contents: "v1")
        defer { Self.cleanup(url) }

        let counter = FireCounter()
        let watcher = FileWatcher(url: url) { counter.increment() }
        #expect(watcher != nil)

        try await Task.sleep(nanoseconds: 300_000_000)

        try FileManager.default.removeItem(at: url)
        _ = await Self.waitUntil(timeout: 2.0) { counter.count >= 1 }
        let afterDelete = counter.count

        try "v2".write(to: url, atomically: false, encoding: .utf8)
        let afterRecreate = await Self.waitUntil(timeout: 2.0) { counter.count > afterDelete }

        #expect(afterRecreate, "Watcher should fire when the file is recreated after deletion. Fires: delete=\(afterDelete), after recreate=\(counter.count)")

        watcher?.stop()
    }

    @Test("Does not fire after stop()")
    func stopsFiringAfterStop() async throws {
        let url = try Self.makeTempFile(contents: "v1")
        defer { Self.cleanup(url) }

        let counter = FireCounter()
        let watcher = FileWatcher(url: url) { counter.increment() }
        #expect(watcher != nil)

        try await Task.sleep(nanoseconds: 300_000_000)
        watcher?.stop()
        try await Task.sleep(nanoseconds: 200_000_000)

        let beforeWrite = counter.count
        try "v2".write(to: url, atomically: false, encoding: .utf8)
        try await Task.sleep(nanoseconds: 800_000_000)

        #expect(counter.count == beforeWrite, "Watcher should not fire after stop(). Fires before=\(beforeWrite), after=\(counter.count)")
    }

    @Test("Rejects non-file URLs")
    func rejectsNonFileURL() {
        let url = URL(string: "https://example.com/doc.md")!
        let watcher = FileWatcher(url: url) { }
        #expect(watcher == nil)
    }

    @Test("Fires when target is a symlink and the real file is modified")
    func firesThroughSymlink() async throws {
        let realURL = try Self.makeTempFile(contents: "v1")
        defer { Self.cleanup(realURL) }

        // Create a symlink in a different directory pointing at the real file.
        let symlinkDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voidreader-symlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: symlinkDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: symlinkDir) }

        let symlinkURL = symlinkDir.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: realURL)

        let counter = FireCounter()
        let watcher = FileWatcher(url: symlinkURL) { counter.increment() }
        #expect(watcher != nil, "Watcher should initialise for a symlinked target")

        try await Task.sleep(nanoseconds: 300_000_000)

        // Modify the real file (not the symlink). Our watcher must resolve the
        // symlink and watch the REAL file's parent, or this fires zero times.
        try "v2".write(to: realURL, atomically: false, encoding: .utf8)

        let fired = await Self.waitUntil(timeout: 3.0) { counter.count >= 1 }
        #expect(fired, "Watcher on a symlink must fire when the real file changes")

        watcher?.stop()
    }
}

@Suite("URL File Modification Date Tests")
struct URLFileModificationDateTests {

    @Test("Modification date matches filesystem and advances after a write")
    func modificationDateAdvances() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voidreader-moddate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("doc.md")
        try "v1".write(to: url, atomically: false, encoding: .utf8)

        // Compare the extension's answer against the FileManager's ground truth,
        // which is what matters for change detection.
        let fsAttrs1 = try FileManager.default.attributesOfItem(atPath: url.path)
        let fsDate1 = fsAttrs1[.modificationDate] as? Date
        let ext1 = url.fileModificationDate
        #expect(fsDate1 != nil)
        #expect(ext1 != nil)
        if let fsDate1 = fsDate1, let ext1 = ext1 {
            #expect(abs(ext1.timeIntervalSince(fsDate1)) < 0.01, "Extension should match filesystem mtime")
        }

        // Sleep long enough to cross a whole-second boundary on filesystems
        // that round mtime to the second.
        Thread.sleep(forTimeInterval: 2.1)

        try "v2".write(to: url, atomically: false, encoding: .utf8)

        let fsDate2 = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        #expect(fsDate2 != nil)
        if let fsDate1 = fsDate1, let fsDate2 = fsDate2 {
            #expect(fsDate2 > fsDate1, "Ground-truth mtime should advance after a write with >2s separation")
        }
    }

    @Test("Returns nil for a non-existent file")
    func nilForMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voidreader-nope-\(UUID().uuidString).md")
        #expect(url.fileModificationDate == nil)
    }
}
