import AppKit
import Foundation
import SwiftUI
import VoidReaderCore

/// Document-wide height accounting with a prefix-sum index. The sum of
/// block heights is the authoritative "how tall is this document" number
/// used to compute scroll percentage.
///
/// ## Why this exists
/// `LazyVStack` doesn't materialize all rows up front, so SwiftUI's
/// `GeometryReader` on the VStack background reports a content height
/// that only includes *materialized* rows (plus a LazyVStack-internal
/// estimate for the rest, which can be very wrong when row heights vary
/// by orders of magnitude — a text paragraph vs a 6000-line code block).
/// That's why the scroll percentage was jumping from 52% → 100% as the
/// user scrolled into unmaterialized regions: `offset / contentHeight`
/// divided a near-accurate numerator by an under-reported denominator.
///
/// This index sidesteps SwiftUI's layout entirely: for each block we
/// know either the authoritative measured height (from
/// `CodeBlockMeasurementCache`) or a per-block-type fallback estimate
/// (from `BlockHeightCache.defaultEstimates`). The sum is a stable
/// approximation that does *not* depend on scroll position, and
/// converges to exact as measurements land.
///
/// ## Concurrency
/// `@MainActor` because scroll-percentage reads happen inside synchronous
/// SwiftUI view updates and an actor hop would be intolerable latency.
/// All writes already come from `@MainActor` callbacks (measurement
/// completion hops to main before recording), so the main-isolation
/// constraint holds naturally.
///
/// ## Publishing model
/// Only `totalHeight` and `version` are `@Published`. The `prefix` array
/// stays private — views that need to observe the index (e.g. the scroll
/// tracker) observe `version` and re-read what they need. This keeps
/// unrelated views from re-rendering every time a single block's height
/// lands.
@MainActor
final class DocumentHeightIndex: ObservableObject {
    /// Total document height: sum of all block heights (measured or
    /// fallback). The denominator for scroll-percentage calculations.
    @Published private(set) var totalHeight: CGFloat = 0

    /// Monotonic counter bumped on every rebuild. Observers that need to
    /// recompute derived values (scroll percent, block-at-offset lookups)
    /// watch this and re-query.
    @Published private(set) var version: Int = 0

    /// Measured heights, keyed by block index. Populated by
    /// `recordHeight(_:at:)` as measurements land from the off-main
    /// scheduler.
    private var measured: [Int: CGFloat] = [:]

    /// Prefix sum where `prefix[i]` is the cumulative height of blocks
    /// `0..<i`. `prefix[blockCount] == totalHeight`. O(1) lookups for
    /// "what's the y-offset of block N?" via `offset(beforeBlock:)`.
    private var prefix: [CGFloat] = [0]

    /// Current block count. Reset on `configure(...)`.
    private var blockCount: Int = 0

    /// Per-block-type fallback estimator. Captured on `configure(...)` so
    /// rebuilds don't need to re-resolve the block array.
    private var fallbackProvider: ((Int) -> CGFloat)?

    /// Debounce gate: coalesces back-to-back `recordHeight` calls into
    /// one rebuild per run-loop tick, turning O(N²) in a prefetch storm
    /// into O(N).
    private var pendingRebuild = false

    /// Per-pair spacing provider. `spacingProvider(i)` returns the spacing
    /// inserted above block `i` (i.e. between blocks `i - 1` and `i`).
    /// Block 0 is expected to return 0. The reader uses this to collapse
    /// spacing between same-group code segments so the index's totalHeight
    /// matches the live layout (otherwise the scroll-percent math drifts
    /// by 16pt per collapsed seam).
    private var spacingProvider: (Int) -> CGFloat = { _ in 16 }

    // MARK: - Configuration

    /// Reset the index for a new document / re-render. Captures the
    /// fallback provider (which closes over the current block list) and
    /// performs an initial rebuild so `totalHeight` is populated
    /// immediately.
    func configure(
        blockCount: Int,
        blockSpacing: CGFloat,
        fallback: @escaping (Int) -> CGFloat,
        spacingProvider: ((Int) -> CGFloat)? = nil
    ) {
        self.blockCount = blockCount
        // If the caller supplies an explicit spacing provider, use it;
        // otherwise use a constant `blockSpacing` so pre-segmentation call
        // sites keep working unchanged.
        self.spacingProvider = spacingProvider ?? { index in
            index > 0 ? blockSpacing : 0
        }
        self.fallbackProvider = fallback
        self.measured.removeAll()
        rebuildNow()
    }

    // MARK: - Writes

    /// Record an authoritative measured height for a block. Debounced —
    /// the prefix sum rebuilds at most once per run-loop tick, so a
    /// prefetch storm that lands N results back-to-back produces one
    /// rebuild, not N.
    ///
    /// The 2pt epsilon: tiny deltas are suppressed entirely. Prevents
    /// "micro-jump" animations when a measurement lands that's within a
    /// pixel or two of the existing fallback/measured value. Matches
    /// `BlockHeightCache.record` behavior.
    func recordHeight(_ h: CGFloat, at index: Int) {
        if let existing = measured[index], abs(existing - h) < 2 {
            return
        }
        measured[index] = h
        scheduleRebuild()
    }

    // MARK: - Reads

    /// Y-offset where block `i` starts. O(1).
    func offset(beforeBlock i: Int) -> CGFloat {
        let clamped = max(0, min(i, prefix.count - 1))
        return prefix[clamped]
    }

    /// Find the block index nearest a given scroll offset. Binary search
    /// over `prefix` — O(log N). Used by the scroll tracker to map a
    /// pixel offset back to "which block is the user looking at."
    func blockIndex(atOffset offset: CGFloat) -> Int {
        guard blockCount > 0 else { return 0 }
        // Lower bound search over prefix[1..<prefix.count].
        var lo = 0
        var hi = blockCount
        while lo < hi {
            let mid = (lo + hi) / 2
            if prefix[mid + 1] <= offset {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return min(lo, blockCount - 1)
    }

    /// Scroll percentage as a clamped fraction in `[0, 1]`. Guards against
    /// divide-by-zero (empty doc) and `NaN` (negative offsets during
    /// bounce scrolling on macOS).
    ///
    /// The denominator is `totalHeight - visibleHeight` (the *scrollable*
    /// range), matching NSScrollView's own convention: at scroll 0 the
    /// user sees the top, at scrollable-max they see the bottom. If the
    /// document fits the viewport, scroll % is 0 by definition.
    ///
    /// `outerChrome` accounts for non-block height in the scroll
    /// container that the index doesn't track — e.g. padding around the
    /// reader view, anchor spacers, etc. Added to `totalHeight` so the
    /// denominator matches the real scrollable range.
    func scrollFraction(offset: CGFloat, visibleHeight: CGFloat, outerChrome: CGFloat = 0) -> Double {
        let effective = totalHeight + outerChrome
        let scrollable = max(effective - visibleHeight, 1)
        guard effective > visibleHeight else { return 0 }
        let raw = Double(offset / scrollable)
        return min(max(raw, 0), 1)
    }

    // MARK: - Rebuild

    /// Force a synchronous rebuild. Exposed for unit tests that record
    /// heights and need to inspect `totalHeight` immediately without
    /// waiting for the debounced `Task` to run.
    func flushForTesting() {
        rebuildNow()
        pendingRebuild = false
    }

    private func scheduleRebuild() {
        guard !pendingRebuild else { return }
        pendingRebuild = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.rebuildNow()
            self.pendingRebuild = false
        }
    }

    private func rebuildNow() {
        guard let fallback = fallbackProvider else {
            prefix = [0]
            totalHeight = 0
            version &+= 1
            return
        }
        var p = [CGFloat](repeating: 0, count: blockCount + 1)
        for i in 0..<blockCount {
            let raw = measured[i] ?? fallback(i)
            // Spacing sits *above* each block — `spacingProvider(i)` gives
            // the gap between blocks `i - 1` and `i`, so block 0 contributes
            // 0. This mirrors the reader's per-row `.padding(.top, ...)`
            // scheme exactly, so totalHeight stays aligned with the live
            // LazyVStack layout even when same-group code segments collapse
            // their spacing to 0.
            let spacing = spacingProvider(i)
            p[i + 1] = p[i] + spacing + raw
        }
        prefix = p
        totalHeight = blockCount > 0 ? p[blockCount] : 0
        version &+= 1
    }
}

// MARK: - SwiftUI Environment

private struct DocumentHeightIndexKey: EnvironmentKey {
    static let defaultValue: DocumentHeightIndex? = nil
}

extension EnvironmentValues {
    /// Document-wide height index. Injected from `ContentView` onto the
    /// reader view tree; observers (scroll tracker, jump-to-block) read
    /// it rather than summing heights themselves.
    var documentHeightIndex: DocumentHeightIndex? {
        get { self[DocumentHeightIndexKey.self] }
        set { self[DocumentHeightIndexKey.self] = newValue }
    }
}

// MARK: - Fallback helpers

extension DocumentHeightIndex {
    /// Build a fallback height provider for a block array. Uses the
    /// per-type estimates from `BlockHeightCache` for non-code blocks,
    /// and a line-count × font-metric estimate for code blocks (same
    /// formula as `CodeBlockView.placeholderHeight` so the gate→measured
    /// swap is smooth).
    static func defaultFallback(
        for blocks: [MarkdownBlock],
        codeFont: NSFont
    ) -> (Int) -> CGFloat {
        let lineHeight = ceil(codeFont.ascender - codeFont.descender + codeFont.leading)
        return { index in
            guard index < blocks.count else { return 80 }
            let block = blocks[index]
            switch block {
            case .codeBlock(let data):
                var lines = 1
                for char in data.code where char == "\n" { lines += 1 }
                let chrome = CodeBlockView.chromeHeight(
                    isFirst: data.isSegmentFirst,
                    isLast: data.isSegmentLast
                )
                return CGFloat(lines) * lineHeight + chrome
            default:
                return block.estimatedHeight
            }
        }
    }
}
