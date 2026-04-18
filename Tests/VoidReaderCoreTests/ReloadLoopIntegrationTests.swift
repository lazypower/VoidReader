import Testing
import Foundation
@testable import VoidReaderCore

/// Integration tests that compose the reload subsystem end-to-end WITHOUT SwiftUI:
/// real temp filesystem, real `FileWatcher` (FSEventStream), real policy types.
///
/// These catch bugs that unit tests on each layer cannot:
///   - The watcher and the detector disagreeing on what "current mod date" is
///   - The watcher dying after one event (our original bug)
///   - The detector computing against a stale baseline after a reload
///   - Own-save suppression not composing with watcher callbacks
///
/// If these pass but the app still misbehaves, the bug is in SwiftUI wiring
/// (NSDocument bridge, binding propagation) — and THAT is the UI-test layer's job.
@Suite("Reload Loop Integration")
struct ReloadLoopIntegrationTests {

    // MARK: - Helpers (duplicated from FileWatcherTests to keep suites independently runnable)

    private static func makeTempFile(contents: String = "initial") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voidreader-reload-loop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("doc.md")
        try contents.write(to: url, atomically: false, encoding: .utf8)
        return url
    }

    private static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private static func atomicRenameSave(contents: String, to url: URL) throws {
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".tmp-\(UUID().uuidString)")
        try contents.write(to: tempURL, atomically: false, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    private static func waitUntil(timeout: TimeInterval, _ predicate: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return predicate()
    }

    private final class FireCounter: @unchecked Sendable {
        private var _count = 0
        private let lock = NSLock()
        func increment() { lock.lock(); _count += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    }

    // MARK: - Tests

    /// The marquee integration test: simulates the complete
    /// "external change → prompt → reload → later external change" loop
    /// and asserts the policy types return the correct resolution at each stage.
    @Test("Two consecutive atomic saves each produce externalChange with correct baseline handling")
    func twoConsecutiveExternalChanges() async throws {
        let url = try Self.makeTempFile(contents: "v1")
        defer { Self.cleanup(url) }

        var lastKnownModDate = url.fileModificationDate
        #expect(lastKnownModDate != nil, "Baseline mod date must be readable")

        let counter = FireCounter()
        let watcher = FileWatcher(url: url) { counter.increment() }
        #expect(watcher != nil)

        try await Task.sleep(nanoseconds: 300_000_000)

        // Stage 1: pristine — no change yet
        #expect(
            ExternalChangeDetector.resolve(
                currentModDate: url.fileModificationDate,
                lastKnownModDate: lastKnownModDate,
                isOwnSaveInProgress: false
            ) == .noChange,
            "Before any external change, detector must return .noChange"
        )
        #expect(
            SaveConflictPolicy.isSafeToSave(
                currentModDate: url.fileModificationDate,
                lastKnownModDate: lastKnownModDate
            ),
            "Before any external change, saving must be safe"
        )

        // Cross a whole-second boundary so mtime advances on second-precision filesystems.
        Thread.sleep(forTimeInterval: 2.1)

        // Stage 2: first external atomic-rename save
        try Self.atomicRenameSave(contents: "v2", to: url)
        let fired1 = await Self.waitUntil(timeout: 3.0) { counter.count >= 1 }
        #expect(fired1, "Watcher must fire after first atomic save. Fires: \(counter.count)")

        #expect(
            ExternalChangeDetector.resolve(
                currentModDate: url.fileModificationDate,
                lastKnownModDate: lastKnownModDate,
                isOwnSaveInProgress: false
            ) == .externalChange,
            "After external change, detector must return .externalChange"
        )
        #expect(
            !SaveConflictPolicy.isSafeToSave(
                currentModDate: url.fileModificationDate,
                lastKnownModDate: lastKnownModDate
            ),
            "With a stale baseline, saving must be blocked"
        )

        // Stage 3: simulate user clicking Reload — app updates baseline to current.
        lastKnownModDate = url.fileModificationDate

        #expect(
            ExternalChangeDetector.resolve(
                currentModDate: url.fileModificationDate,
                lastKnownModDate: lastKnownModDate,
                isOwnSaveInProgress: false
            ) == .noChange,
            "After reload refreshes the baseline, detector must return .noChange"
        )
        #expect(
            SaveConflictPolicy.isSafeToSave(
                currentModDate: url.fileModificationDate,
                lastKnownModDate: lastKnownModDate
            ),
            "After reload refreshes the baseline, saving must be safe again"
        )

        // Stage 4: SECOND atomic save — regression test for the original bug
        // where the fd-based watcher died after the first rename.
        Thread.sleep(forTimeInterval: 2.1)
        try Self.atomicRenameSave(contents: "v3", to: url)
        let fired2 = await Self.waitUntil(timeout: 3.0) { counter.count >= 2 }
        #expect(fired2, "Watcher must fire on the SECOND atomic save (original bug: it didn't). Fires: \(counter.count)")

        #expect(
            ExternalChangeDetector.resolve(
                currentModDate: url.fileModificationDate,
                lastKnownModDate: lastKnownModDate,
                isOwnSaveInProgress: false
            ) == .externalChange,
            "Second external change must be detected against the refreshed baseline"
        )

        watcher?.stop()
    }

    /// Verifies that when the app's own save is in progress, a FileWatcher event
    /// does not trigger an external-change prompt, and the baseline advances to
    /// the new mod date so the next real external change is still detected.
    @Test("Own save is suppressed but refreshes baseline; subsequent external change still detected")
    func ownSaveThenExternalChange() async throws {
        let url = try Self.makeTempFile(contents: "v1")
        defer { Self.cleanup(url) }

        var lastKnownModDate = url.fileModificationDate
        var isOwnSaveInProgress = false

        let counter = FireCounter()
        let watcher = FileWatcher(url: url) { counter.increment() }
        #expect(watcher != nil)

        try await Task.sleep(nanoseconds: 300_000_000)

        // App save begins — suppression on.
        isOwnSaveInProgress = true
        Thread.sleep(forTimeInterval: 2.1)
        try Self.atomicRenameSave(contents: "v2-by-us", to: url)
        _ = await Self.waitUntil(timeout: 3.0) { counter.count >= 1 }
        #expect(counter.count >= 1, "Watcher must fire regardless of suppression")

        // Detector must report .ownSaveInProgress, not .externalChange.
        let duringSave = ExternalChangeDetector.resolve(
            currentModDate: url.fileModificationDate,
            lastKnownModDate: lastKnownModDate,
            isOwnSaveInProgress: isOwnSaveInProgress
        )
        #expect(duringSave == .ownSaveInProgress)

        // App updates baseline (as production code does inside the .ownSaveInProgress branch)
        // and clears the suppression flag.
        lastKnownModDate = url.fileModificationDate
        isOwnSaveInProgress = false

        // Now a real external change must be detected against the new baseline.
        Thread.sleep(forTimeInterval: 2.1)
        try Self.atomicRenameSave(contents: "v3-external", to: url)
        let fired2 = await Self.waitUntil(timeout: 3.0) { counter.count >= 2 }
        #expect(fired2, "Watcher must fire on the subsequent external save")

        let afterExternal = ExternalChangeDetector.resolve(
            currentModDate: url.fileModificationDate,
            lastKnownModDate: lastKnownModDate,
            isOwnSaveInProgress: false
        )
        #expect(afterExternal == .externalChange, "External change after own-save must be detected, not swallowed by a stale baseline")

        watcher?.stop()
    }

    /// Verifies the loop works across a file-watcher lifecycle boundary:
    /// the watcher is stopped and re-started (as would happen if the user
    /// closed and reopened the document), and the detector computes correctly
    /// against the fresh baseline.
    @Test("Watcher restart preserves detector correctness across lifecycle")
    func watcherRestart() async throws {
        let url = try Self.makeTempFile(contents: "v1")
        defer { Self.cleanup(url) }

        // First lifecycle
        let counter1 = FireCounter()
        let watcher1 = FileWatcher(url: url) { counter1.increment() }
        try await Task.sleep(nanoseconds: 300_000_000)
        Thread.sleep(forTimeInterval: 2.1)
        try Self.atomicRenameSave(contents: "v2", to: url)
        _ = await Self.waitUntil(timeout: 3.0) { counter1.count >= 1 }
        #expect(counter1.count >= 1)
        watcher1?.stop()

        // Second lifecycle — fresh watcher, fresh baseline
        let lastKnownModDate = url.fileModificationDate
        let counter2 = FireCounter()
        let watcher2 = FileWatcher(url: url) { counter2.increment() }
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(
            ExternalChangeDetector.resolve(
                currentModDate: url.fileModificationDate,
                lastKnownModDate: lastKnownModDate,
                isOwnSaveInProgress: false
            ) == .noChange,
            "Fresh baseline on a newly-started watcher must report .noChange"
        )

        Thread.sleep(forTimeInterval: 2.1)
        try Self.atomicRenameSave(contents: "v3", to: url)
        let fired = await Self.waitUntil(timeout: 3.0) { counter2.count >= 1 }
        #expect(fired, "Second-lifecycle watcher must still fire on external change")

        #expect(
            ExternalChangeDetector.resolve(
                currentModDate: url.fileModificationDate,
                lastKnownModDate: lastKnownModDate,
                isOwnSaveInProgress: false
            ) == .externalChange
        )

        watcher2?.stop()
    }
}
