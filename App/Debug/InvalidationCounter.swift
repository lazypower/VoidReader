#if DEBUG
import Foundation
import os
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
/// Usage, at the top of an instrumented `body`:
///
/// ```swift
/// var body: some View {
///     let _ = InvalidationCounter.tick("BlockView")
///     // ... rest of body
/// }
/// ```
///
/// Ownership rule: whoever modifies an instrumented view (`BlockView`,
/// `ContentView`, `MarkdownReaderView`) is responsible for verifying the
/// counter still reports sensible numbers post-change. Reviewers enforce
/// on PRs touching these views. See DEVELOPMENT.md "Invalidation Counters".
public enum InvalidationCounter {

    private static let queue = DispatchQueue(label: "place.wabash.VoidReader.invalidationCounter")
    private static var counts: [String: Int] = [:]
    private static var lastReportedAt: [String: Date] = [:]

    /// Minimum interval between DebugLog emissions for the same view name.
    /// Throttles the console when a view churns without throttling the
    /// underlying count.
    private static let reportThrottle: TimeInterval = 1.0

    /// Increment the counter for the named view. Call at the top of `body`.
    /// Returns Void so it's safe to assign via `let _ = tick(...)`.
    @discardableResult
    public static func tick(_ viewName: String) -> Int {
        queue.sync {
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
