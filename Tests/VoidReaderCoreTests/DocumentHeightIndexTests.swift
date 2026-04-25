import Testing
import CoreGraphics
#if canImport(VoidReader)
@testable import VoidReader
#endif
@testable import VoidReaderCore

#if canImport(VoidReader)
@Suite("DocumentHeightIndex Scroll Fraction")
struct DocumentHeightIndexTests {

    // MARK: - Helpers

    /// Build a block list with the given code line counts. Non-code blocks
    /// are interspersed as text blocks with a fixed estimated height.
    private static func makeBlocks(codeLineCounts: [Int]) -> [MarkdownBlock] {
        // Build a minimal markdown string with code blocks of known sizes
        var markdown = "# Heading\n\nSome intro text.\n\n"
        for lines in codeLineCounts {
            let code = (0..<lines).map { "line \($0)" }.joined(separator: "\n")
            markdown += "```swift\n\(code)\n```\n\nSome text between blocks.\n\n"
        }
        return BlockRenderer.render(markdown)
    }

    // MARK: - Basic scrollFraction behavior

    @Test("scrollFraction returns 0 when document fits viewport")
    @MainActor func fitsViewport() {
        let index = DocumentHeightIndex()
        index.configure(blockCount: 2, blockSpacing: 16, fallback: { _ in 100 })
        // totalHeight = 0 + 100 + 16 + 100 = 216
        let fraction = index.scrollFraction(offset: 0, visibleHeight: 1000)
        #expect(fraction == 0)
    }

    @Test("scrollFraction returns 1.0 at max offset")
    @MainActor func maxOffset() {
        let index = DocumentHeightIndex()
        index.configure(blockCount: 5, blockSpacing: 16, fallback: { _ in 200 })
        // totalHeight = 200 + (16+200)*4 = 200 + 864 = 1064
        let visibleHeight: CGFloat = 400
        let maxOffset = index.totalHeight - visibleHeight
        let fraction = index.scrollFraction(offset: maxOffset, visibleHeight: visibleHeight)
        #expect(fraction == 1.0)
    }

    @Test("scrollFraction returns 1.0 at max offset with outerChrome")
    @MainActor func maxOffsetWithOuterChrome() {
        let index = DocumentHeightIndex()
        index.configure(blockCount: 5, blockSpacing: 16, fallback: { _ in 200 })
        let visibleHeight: CGFloat = 400
        let outerChrome: CGFloat = 81  // typical: 40*2 padding + 1 anchor
        let maxOffset = index.totalHeight + outerChrome - visibleHeight
        let fraction = index.scrollFraction(
            offset: maxOffset,
            visibleHeight: visibleHeight,
            outerChrome: outerChrome
        )
        #expect(fraction == 1.0)
    }

    @Test("scrollFraction without outerChrome overshoots when offset includes chrome")
    @MainActor func overshootWithoutChrome() {
        // This test captures the bug: if outer chrome is not accounted for,
        // the fraction exceeds 1.0 (clamped) before the user reaches the
        // bottom — the percentage "completes too early."
        let index = DocumentHeightIndex()
        index.configure(blockCount: 10, blockSpacing: 16, fallback: { _ in 300 })
        let visibleHeight: CGFloat = 600
        let outerChrome: CGFloat = 81

        // At 90% of the real scrollable range, the fraction should be ~0.9.
        let realScrollable = index.totalHeight + outerChrome - visibleHeight
        let offset = realScrollable * 0.9

        // Without chrome: denominator is too small, fraction overshoots
        let fractionWithout = index.scrollFraction(offset: offset, visibleHeight: visibleHeight)
        // With chrome: denominator is correct, fraction is accurate
        let fractionWith = index.scrollFraction(
            offset: offset,
            visibleHeight: visibleHeight,
            outerChrome: outerChrome
        )

        #expect(fractionWith < 1.0, "With chrome, 90% offset should not saturate to 100%")
        #expect(fractionWith > fractionWithout * 0.95, "Fractions should be close but chrome-adjusted is smaller")
        // The without-chrome fraction is larger because the denominator is smaller
        #expect(fractionWithout > fractionWith)
    }

    // MARK: - Measurement recording regression

    @Test("totalHeight does not decrease when authoritative measurements include chrome")
    @MainActor func measurementWithChromeDoesNotShrinkTotal() {
        // Simulates the prefetch path: fallback estimates include chrome,
        // authoritative measurements must also include chrome. If they
        // don't, totalHeight drops and the scroll percentage completes
        // early. This is the core regression test for issue #2.
        let index = DocumentHeightIndex()

        // Simulate 3 non-segmented code blocks + 2 text blocks
        // Code blocks: first and last segment (non-segmented = both)
        // Chrome per non-segmented code block: 12 + 24 (first) + 12 (last) = 48
        let codeLineHeight: CGFloat = 16  // approximate
        let codeLinesPerBlock = 100
        let codeTextHeight = CGFloat(codeLinesPerBlock) * codeLineHeight  // 1600
        let codeChrome: CGFloat = 48  // 12 + 24 + 12

        let fallback: (Int) -> CGFloat = { i in
            if i == 0 || i == 2 || i == 4 {
                // Code blocks: line estimate + chrome (matches defaultFallback)
                return CGFloat(codeLinesPerBlock) * codeLineHeight + codeChrome
            } else {
                // Text blocks
                return 80
            }
        }

        index.configure(blockCount: 5, blockSpacing: 16, fallback: fallback)
        let initialTotal = index.totalHeight

        // Simulate authoritative measurements landing WITH chrome
        // (TextKit height differs slightly from line-count estimate)
        let measuredTextHeight: CGFloat = codeTextHeight + 3  // slight TextKit variance
        index.recordHeight(measuredTextHeight + codeChrome, at: 0)
        index.recordHeight(measuredTextHeight + codeChrome, at: 2)
        index.recordHeight(measuredTextHeight + codeChrome, at: 4)
        index.flushForTesting()  // force sync rebuild (recordHeight is debounced)

        // The key invariant: totalHeight should NOT decrease
        #expect(
            index.totalHeight >= initialTotal - 10,
            "totalHeight should not decrease when measurements land (was \(initialTotal), now \(index.totalHeight))"
        )
    }

    @Test("totalHeight DOES decrease when measurements omit chrome (captures the bug)")
    @MainActor func measurementWithoutChromeBreaks() {
        // This test demonstrates the bug condition: if authoritative
        // measurements record only the text height (no chrome), totalHeight
        // drops significantly. This is what was happening before the fix.
        let index = DocumentHeightIndex()

        let codeLineHeight: CGFloat = 16
        let codeLinesPerBlock = 100
        let codeTextHeight = CGFloat(codeLinesPerBlock) * codeLineHeight
        let codeChrome: CGFloat = 48

        let fallback: (Int) -> CGFloat = { i in
            if i == 0 || i == 2 || i == 4 {
                return CGFloat(codeLinesPerBlock) * codeLineHeight + codeChrome
            } else {
                return 80
            }
        }

        index.configure(blockCount: 5, blockSpacing: 16, fallback: fallback)
        let initialTotal = index.totalHeight

        // Record measurements WITHOUT chrome — the bug
        index.recordHeight(codeTextHeight, at: 0)
        index.recordHeight(codeTextHeight, at: 2)
        index.recordHeight(codeTextHeight, at: 4)
        index.flushForTesting()

        // totalHeight should drop by ~3 * chrome = 144pt
        let drop = initialTotal - index.totalHeight
        #expect(
            drop > 100,
            "Without chrome, totalHeight should drop significantly (was \(initialTotal), now \(index.totalHeight), drop=\(drop))"
        )
    }

    // MARK: - Linear scaling

    @Test("scrollFraction scales linearly across full range")
    @MainActor func linearScaling() {
        let index = DocumentHeightIndex()
        index.configure(blockCount: 20, blockSpacing: 16, fallback: { _ in 200 })
        let visibleHeight: CGFloat = 500
        let outerChrome: CGFloat = 81
        let scrollable = index.totalHeight + outerChrome - visibleHeight

        for pct in stride(from: 0.0, through: 1.0, by: 0.1) {
            let offset = scrollable * pct
            let fraction = index.scrollFraction(
                offset: offset,
                visibleHeight: visibleHeight,
                outerChrome: outerChrome
            )
            #expect(
                abs(fraction - pct) < 0.01,
                "At \(Int(pct * 100))% offset, fraction should be ~\(pct) but was \(fraction)"
            )
        }
    }

    // MARK: - Progressive render regression

    @Test("Reconfigure with more blocks increases totalHeight and reduces scrollFraction")
    @MainActor func progressiveRenderReconfigure() {
        // Simulates the progressive render bug:
        // 1. Initial chunk: 3 blocks, small totalHeight
        // 2. User is near bottom → scrollFraction ≈ 1.0
        // 3. Background render completes: 200 blocks, large totalHeight
        // 4. Same offset → scrollFraction should drop dramatically
        //
        // The actual bug was that step 4 never happened because
        // updateScrollPercent wasn't called after reconfigure.
        let index = DocumentHeightIndex()
        let visibleHeight: CGFloat = 375
        let outerChrome: CGFloat = 81

        // Step 1: initial chunk (3 blocks, ~442pt like the debug log showed)
        index.configure(blockCount: 3, blockSpacing: 16, fallback: { _ in 140 })
        let initialTotal = index.totalHeight
        #expect(initialTotal < 500, "Initial chunk should be small")

        // Step 2: user scrolls a tiny bit — with only 3 blocks, this is near 100%
        let offset: CGFloat = 144
        let initialFraction = index.scrollFraction(
            offset: offset,
            visibleHeight: visibleHeight,
            outerChrome: outerChrome
        )
        #expect(initialFraction > 0.9, "With 3 blocks, offset 144 should read ~100% (got \(initialFraction))")

        // Step 3: background render completes, reconfigure with full document
        index.configure(blockCount: 200, blockSpacing: 16, fallback: { _ in 140 })
        let fullTotal = index.totalHeight
        #expect(fullTotal > initialTotal * 10, "Full document should be much taller")

        // Step 4: SAME offset, but now with correct denominator
        let updatedFraction = index.scrollFraction(
            offset: offset,
            visibleHeight: visibleHeight,
            outerChrome: outerChrome
        )
        #expect(
            updatedFraction < 0.05,
            "After reconfigure, offset 144 in a huge doc should be near 0% (got \(updatedFraction))"
        )
    }

    @Test("scrollFraction returns 0 when totalHeight is 0 (no blocks yet)")
    @MainActor func zeroBlocksReturnsZero() {
        // Before any blocks are rendered, totalHeight is 0.
        // scrollFraction must return 0, not NaN or 100%.
        let index = DocumentHeightIndex()
        let fraction = index.scrollFraction(offset: 0, visibleHeight: 600)
        #expect(fraction == 0, "Empty index should return 0% (got \(fraction))")
    }

    @Test("scrollFraction returns 0 when visibleHeight not yet measured")
    @MainActor func zeroVisibleHeightReturnsZero() {
        // On first layout pass, visibleHeight may still be 0.
        let index = DocumentHeightIndex()
        index.configure(blockCount: 10, blockSpacing: 16, fallback: { _ in 200 })
        let fraction = index.scrollFraction(offset: 0, visibleHeight: 0, outerChrome: 81)
        #expect(fraction == 0, "With visibleHeight=0 at offset 0, should return 0% (got \(fraction))")
    }
}
#endif
