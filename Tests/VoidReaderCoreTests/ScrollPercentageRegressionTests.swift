import Testing
import CoreGraphics
@testable import VoidReaderCore

@Suite("Scroll Percentage Regressions")
struct ScrollPercentageRegressionTests {

    // MARK: - Progressive render precondition

    /// Helper: builds a markdown document guaranteed to exceed the chunker's
    /// 20KB target, so `findFirstChunkEnd` returns a proper prefix boundary.
    private static func makeLargeMarkdown() -> String {
        // Each paragraph is ~80 chars. 500 paragraphs ≈ 40KB, well over the
        // 20KB chunking threshold.
        var markdown = "# Large Document\n\n"
        for i in 0..<500 {
            markdown += "## Section \(i)\n\nParagraph \(i): " + String(repeating: "word ", count: 20) + "\n\n"
        }
        return markdown
    }

    /// The scroll% bug requires that a partial render produces significantly
    /// fewer blocks than the full document. This test proves that precondition
    /// holds, so the regression tests below are meaningful.
    @Test("Partial render of large document produces fewer blocks than full render")
    func partialRenderFewerBlocks() {
        let markdown = Self.makeLargeMarkdown()
        // Sanity: document must be larger than chunker threshold
        #expect(markdown.count > 20_000, "Test doc must exceed chunker threshold")

        let firstChunkEnd = MarkdownChunker.findFirstChunkEnd(in: markdown)
        #expect(firstChunkEnd < markdown.count, "Chunker should split the document")

        let firstChunk = String(markdown.prefix(firstChunkEnd))

        let partialBlocks = BlockRenderer.render(firstChunk)
        let fullBlocks = BlockRenderer.render(markdown)

        #expect(
            partialBlocks.count < fullBlocks.count,
            "Partial render (\(partialBlocks.count) blocks) should have fewer blocks than full render (\(fullBlocks.count) blocks)"
        )
    }

    /// The height estimate from partial blocks must be smaller than from the
    /// full document. If the scroll tracker uses the partial estimate as the
    /// denominator, it will report 100% prematurely.
    @Test("Partial block list has less estimated height than full block list")
    func partialHeightSmaller() {
        let markdown = Self.makeLargeMarkdown()
        let firstChunkEnd = MarkdownChunker.findFirstChunkEnd(in: markdown)
        let firstChunk = String(markdown.prefix(firstChunkEnd))

        let partialBlocks = BlockRenderer.render(firstChunk)
        let fullBlocks = BlockRenderer.render(markdown)

        let partialHeight = partialBlocks.reduce(CGFloat(0)) { $0 + $1.estimatedHeight }
        let fullHeight = fullBlocks.reduce(CGFloat(0)) { $0 + $1.estimatedHeight }

        #expect(
            partialHeight < fullHeight,
            "Partial height (\(partialHeight)) should be less than full height (\(fullHeight))"
        )
    }

    // MARK: - The actual bug scenario

    /// Simulates the exact bug: scroll tracker fires against initial chunk's
    /// height, then background render completes with more blocks. The caller
    /// MUST recalculate scroll percent after reconfiguring with the full list,
    /// or the percentage stays stuck at the partial-denominator value.
    ///
    /// This test verifies the invariant at the data level: reconfiguring
    /// with more blocks produces a larger totalHeight, which would reduce
    /// scrollFraction for the same offset. The actual recalculation call
    /// is in ContentView (UI layer, not testable here), but if this
    /// invariant holds, the fix is just "call updateScrollPercent after
    /// reconfigure" — which is what we added.
    @Test("Same offset reads high% against partial blocks, low% against full blocks")
    func fractionDropsAfterReconfigure() {
        let markdown = Self.makeLargeMarkdown()
        let firstChunkEnd = MarkdownChunker.findFirstChunkEnd(in: markdown)
        let firstChunk = String(markdown.prefix(firstChunkEnd))

        let partialBlocks = BlockRenderer.render(firstChunk)
        let fullBlocks = BlockRenderer.render(markdown)

        let partialHeight = partialBlocks.reduce(CGFloat(0)) { sum, block in
            sum + block.estimatedHeight + 16  // spacing
        }
        let fullHeight = fullBlocks.reduce(CGFloat(0)) { sum, block in
            sum + block.estimatedHeight + 16
        }

        // Simulate: user is near the bottom of the initial chunk
        let visibleHeight: CGFloat = 600
        let userOffset: CGFloat = max(partialHeight - visibleHeight, 0)

        let partialScrollable = max(partialHeight - visibleHeight, 1)
        let fullScrollable = max(fullHeight - visibleHeight, 1)

        let fractionWithPartial = min(userOffset / partialScrollable, 1.0)
        let fractionWithFull = min(userOffset / fullScrollable, 1.0)

        #expect(
            fractionWithPartial > 0.8,
            "With partial denominator, user near bottom should read >80% (got \(fractionWithPartial))"
        )
        #expect(
            fractionWithFull < fractionWithPartial * 0.5,
            "With full denominator, fraction should drop significantly (partial=\(fractionWithPartial), full=\(fractionWithFull))"
        )
    }

    // MARK: - Table-heavy document regression

    /// Tables produce a single .table block per table, so a 12k-row table
    /// is one block with estimatedHeight=250. The scroll tracker's denominator
    /// is tiny relative to the actual rendered height. This test ensures
    /// BlockRenderer produces a table block for large tables (the precondition
    /// for the measurement cache to later correct the height).
    @Test("Large table renders as table block, not text")
    func largeTableRendersAsTableBlock() {
        var markdown = "| Col A | Col B |\n|-------|-------|\n"
        for i in 0..<100 {
            markdown += "| Row \(i) | Data \(i) |\n"
        }

        let blocks = BlockRenderer.render(markdown)
        let tableBlocks = blocks.filter { block in
            if case .table = block { return true }
            return false
        }
        #expect(tableBlocks.count == 1, "Should produce exactly one table block")
    }
}
