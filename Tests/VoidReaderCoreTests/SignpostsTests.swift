import Testing
import Foundation
@testable import VoidReaderCore

@Suite("Signposts")
struct SignpostsTests {

    // MARK: - API surface

    @Test("Every category resolves via the switch (exhaustiveness smoke test)")
    func everyCategoryResolves() {
        // The switch in `signposter(for:)` is compiler-checked exhaustive; this just confirms
        // calling it for every case doesn't trap. Distinct configuration is asserted in
        // `subsystemIdentifiersAreStable` below.
        for category in SignpostCategory.allCases {
            _ = Signposts.signposter(for: category)
        }
    }

    @Test("Subsystem identifiers follow the documented pattern")
    func subsystemIdentifiersAreStable() {
        // These identifiers are part of the public contract for Instruments filters.
        // Changing them is a breaking change for existing trace templates / saved filters.
        #expect(Signposts.renderingSubsystem == "place.wabash.VoidReader.rendering")
        #expect(Signposts.lifecycleSubsystem == "place.wabash.VoidReader.lifecycle")
        #expect(Signposts.scrollSubsystem == "place.wabash.VoidReader.scroll")
        #expect(Signposts.mermaidSubsystem == "place.wabash.VoidReader.mermaid")
        #expect(Signposts.imageSubsystem == "place.wabash.VoidReader.image")
    }

    @Test("interval returns the block's value")
    func intervalReturnsBlockValue() {
        let result = Signposts.interval("test.identity", category: .rendering) {
            return 42
        }
        #expect(result == 42)
    }

    @Test("interval rethrows errors")
    func intervalRethrows() {
        struct Boom: Error {}
        do {
            try Signposts.interval("test.throws", category: .rendering) {
                throw Boom()
            }
            Issue.record("Expected throw")
        } catch is Boom {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("event does not throw or block")
    func eventEmitsCleanly() {
        // Smoke test: emitting an event from each category must not crash.
        for category in SignpostCategory.allCases {
            Signposts.event("test.smoke", category: category)
        }
    }

    // MARK: - Zero-overhead contract (task 1.2.2)

    /// Verifies that wrapping work in a signpost interval does not introduce measurable overhead
    /// when Instruments is not recording. This catches accidents like:
    ///   - Forgetting `defer { endInterval(...) }` (causing imbalance)
    ///   - Building format strings eagerly outside an `OSLogMessage`
    ///   - Allocating in the hot path
    ///
    /// The unit of work is a real `MarkdownParser.parse` call (per design.md §2's guidance)
    /// so per-call signpost cost (~1µs) compares against millisecond-scale work and the ratio
    /// stays in a meaningful range. The threshold is intentionally generous (1.5×) — the goal
    /// is catching egregious overhead, not single-digit-percent regressions, which would be
    /// dominated by host noise on shared CI.
    @Test("Signpost interval adds no measurable overhead when not recording")
    func signpostIntervalOverhead() {
        let iterations = 1_000
        let document = """
        # Heading

        A paragraph with **bold**, *italic*, and `inline code`. Plus a [link](https://example.com).

        - item one
        - item two with `code`
        - item three
        """

        func runUninstrumented() -> TimeInterval {
            var sink = 0
            let start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<iterations {
                sink &+= MarkdownParser.parse(document).childCount
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            _ = String(sink).count // keep `sink` live
            return elapsed
        }

        func runInstrumented() -> TimeInterval {
            var sink = 0
            let start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<iterations {
                sink &+= Signposts.interval("benchmark.parse", category: .rendering) {
                    MarkdownParser.parse(document).childCount
                }
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            _ = String(sink).count
            return elapsed
        }

        // Warmup — first iterations include cache effects.
        _ = runUninstrumented()
        _ = runInstrumented()

        // Median of several samples to defang outliers.
        let sampleCount = 5
        let baseline = (0..<sampleCount).map { _ in runUninstrumented() }.sorted()[sampleCount / 2]
        let instrumented = (0..<sampleCount).map { _ in runInstrumented() }.sorted()[sampleCount / 2]

        let ratio = instrumented / baseline
        let baselineMs = baseline * 1000
        let instrumentedMs = instrumented * 1000

        #expect(
            ratio < 1.5,
            """
            Signpost interval overhead too high.
            Baseline (uninstrumented): \(baselineMs) ms
            Instrumented:               \(instrumentedMs) ms
            Ratio:                      \(ratio)
            """
        )
    }

    /// Same shape as above but for `event(_:category:)` — events are emitted from the scroll
    /// loop. We hold the per-iteration workload realistic (a parse call) so per-event overhead
    /// is bounded against meaningful work, not against a single MAD instruction.
    @Test("Signpost event adds no measurable overhead when not recording")
    func signpostEventOverhead() {
        let iterations = 1_000
        let document = """
        # Scroll fixture

        Some text representing a typical block.

        - alpha
        - beta
        """

        func runUninstrumented() -> TimeInterval {
            var sink = 0
            let start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<iterations {
                sink &+= MarkdownParser.parse(document).childCount
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            _ = String(sink).count
            return elapsed
        }

        func runInstrumented() -> TimeInterval {
            var sink = 0
            let start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<iterations {
                sink &+= MarkdownParser.parse(document).childCount
                Signposts.event("benchmark.tick", category: .scroll)
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            _ = String(sink).count
            return elapsed
        }

        _ = runUninstrumented()
        _ = runInstrumented()

        let sampleCount = 5
        let baseline = (0..<sampleCount).map { _ in runUninstrumented() }.sorted()[sampleCount / 2]
        let instrumented = (0..<sampleCount).map { _ in runInstrumented() }.sorted()[sampleCount / 2]

        let ratio = instrumented / baseline
        let baselineMs = baseline * 1000
        let instrumentedMs = instrumented * 1000

        #expect(
            ratio < 1.5,
            """
            Signpost event overhead too high.
            Baseline (uninstrumented): \(baselineMs) ms
            Instrumented:               \(instrumentedMs) ms
            Ratio:                      \(ratio)
            """
        )
    }
}
