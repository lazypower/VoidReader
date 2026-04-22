#if DEBUG
import Foundation
import VoidReaderCore

/// DEBUG-gated SwiftUI `body` recompute counter.
///
/// Increments a per-view tally each time the named `body` executes, and
/// reports the running total via `DebugLog` at a throttled cadence. Intended
/// to surface invalidation-cascade regressions during hunts — a sudden jump
/// in `BlockView` body counts per search-navigate step means "work in body"
/// is amplifying where it shouldn't.
///
/// Excluded from release builds by `#if DEBUG`. No runtime cost in shipping
/// builds. No OSSignpost emission: the point is "show me this number during
/// development," not "feed Instruments."
///
/// ## Opt-in, even in DEBUG
///
/// `tick()` is a no-op unless `VOID_READER_INVALIDATION_COUNTER=1` is set
/// in the environment. Reason: the lab also runs in DEBUG, and
/// `queue.sync { Date() + dict lookup }` on every `body` recompute would
/// perturb the very traces it's meant to observe. The default-off gate
/// keeps the counter ready when a hunt needs it, and absent when the lab
/// is recording.
///
/// Usage, at the top of an instrumented `body`:
///
/// ```swift
/// var body: some View {
///     let _ = InvalidationCounter.tick("BlockView")
///     // ... rest of body
/// }
/// ```
///
/// To enable during a hunt:
///
/// ```bash
/// VOID_READER_INVALIDATION_COUNTER=1 make run-debug
/// ```
///
/// Ownership rule: whoever modifies an instrumented view (`BlockView`,
/// `ContentView`, `MarkdownReaderView`) is responsible for verifying the
/// counter still reports sensible numbers post-change. Reviewers enforce
/// on PRs touching these views. See DEVELOPMENT.md "Invalidation Counters".
public enum InvalidationCounter {

    /// Evaluated once at first use; subsequent `tick()` calls are a single
    /// bool read when disabled. Gated via env var rather than compile flag
    /// so perf-lab runs and development hunts share one binary.
    private static let enabled: Bool = {
        ProcessInfo.processInfo.environment["VOID_READER_INVALIDATION_COUNTER"] == "1"
    }()

    private static let queue = DispatchQueue(label: "place.wabash.VoidReader.invalidationCounter")
    private static var counts: [String: Int] = [:]
    private static var lastReportedAt: [String: Date] = [:]

    /// Minimum interval between DebugLog emissions for the same view name.
    /// Throttles the console when a view churns without throttling the
    /// underlying count.
    private static let reportThrottle: TimeInterval = 1.0

    /// Increment the counter for the named view. Call at the top of `body`.
    /// No-op unless `VOID_READER_INVALIDATION_COUNTER=1` is set.
    /// Returns 0 when disabled (the counter is advisory, not load-bearing).
    @discardableResult
    public static func tick(_ viewName: String) -> Int {
        guard enabled else { return 0 }
        return queue.sync {
            let now = Date()
            let next = (counts[viewName] ?? 0) + 1
            counts[viewName] = next

            let last = lastReportedAt[viewName] ?? .distantPast
            if now.timeIntervalSince(last) >= reportThrottle {
                lastReportedAt[viewName] = now
                DebugLog.log(.rendering, "body-recompute \(viewName)=\(next)")
            }
            return next
        }
    }

    /// Snapshot of current counts. Intended for one-shot reports after a
    /// user-driven action — "how many times did BlockView body run during
    /// this search-navigate step?"
    public static func snapshot() -> [String: Int] {
        queue.sync { counts }
    }

    /// Zero all counters. Useful before a scoped measurement arc.
    public static func reset() {
        queue.sync {
            counts.removeAll()
            lastReportedAt.removeAll()
            DebugLog.log(.rendering, "invalidation counters reset")
        }
    }

    /// Emit the full snapshot as a one-shot report. Call from a debug menu
    /// action or scenario script at the tail of a measurement window.
    public static func report() {
        let snap = snapshot()
        let lines = snap.sorted { $0.value > $1.value }
            .map { "  \($0.key)=\($0.value)" }
            .joined(separator: "\n")
        DebugLog.log(.rendering, "invalidation report:\n\(lines)")
    }
}
#endif
