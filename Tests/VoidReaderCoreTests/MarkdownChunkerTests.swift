import Testing
import Foundation
@testable import VoidReaderCore

@Suite("MarkdownChunker")
struct MarkdownChunkerTests {

    // MARK: - Fast paths

    @Test("Tiny doc returns full length (no chunking needed)")
    func tinyDocNoChunking() {
        let text = "# Small\n\nJust a few paragraphs."
        let end = MarkdownChunker.findFirstChunkEnd(in: text, targetSize: 20_000)
        #expect(end == text.count)
    }

    @Test("Doc exactly at target size returns full length")
    func atExactlyTargetSize() {
        let text = String(repeating: "a", count: 100)
        let end = MarkdownChunker.findFirstChunkEnd(in: text, targetSize: 100)
        #expect(end == text.count)
    }

    // MARK: - Structural-boundary correctness (the whole point)

    /// Regression test for B3: if a code fence crosses the target size, the
    /// cut must land after the fence, not inside it. The old line-boundary
    /// heuristic cut mid-fence, orphaning the rest of the block.
    @Test("Code fence crossing boundary cuts after the fence")
    func codeBlockCrossingBoundary() {
        // 400 lines of "code" — easily enough to cross a small target size.
        let codeBody = (1...400).map { "code line \($0)" }.joined(separator: "\n")
        let text = """
        # Intro

        Some prose here.

        ```swift
        \(codeBody)
        ```

        ## After code

        More prose.
        """

        // Target is smaller than the code block, so the naïve line-boundary
        // heuristic would cut inside the fence. AST-aware chunker must cut
        // at or after the fence's closing ```
        let end = MarkdownChunker.findFirstChunkEnd(in: text, targetSize: 500)

        // The cut must happen AFTER the closing fence.
        let closingFenceOffset = text.range(of: "```\n\n## After code")!.lowerBound
        let closingFenceEnd = text.index(closingFenceOffset, offsetBy: 3)
        let closingFenceEndInt = text.distance(from: text.startIndex, to: closingFenceEnd)

        #expect(end >= closingFenceEndInt,
                "Cut at \(end) must be after closing fence at \(closingFenceEndInt)")

        // And the prefix must itself parse as a complete code block — i.e.,
        // it must contain the closing ``` if it contains the opening one.
        let prefix = String(text.prefix(end))
        if prefix.contains("```swift") {
            let openCount = prefix.components(separatedBy: "```").count - 1
            #expect(openCount % 2 == 0,
                    "Prefix must have balanced fences; got \(openCount) fence markers")
        }
    }

    @Test("Long list crossing boundary cuts after the list")
    func listCrossingBoundary() {
        // Build a list long enough to cross the target.
        let items = (1...300).map { "- item \($0)" }.joined(separator: "\n")
        let text = """
        # Intro

        \(items)

        ## After list

        Trailing prose.
        """

        let end = MarkdownChunker.findFirstChunkEnd(in: text, targetSize: 500)

        // After-list marker must be at or past the cut.
        let afterListOffset = text.distance(
            from: text.startIndex,
            to: text.range(of: "## After list")!.lowerBound
        )
        // Either we cut after the list (>= afterListOffset) or we exposed
        // the whole doc because there was nothing bigger than target before
        // the list started.
        #expect(end >= afterListOffset || end == text.count,
                "Cut at \(end) should land after list (>= \(afterListOffset)) or be full length")
    }

    // MARK: - Degenerate cases

    /// Regression for the torture_100k_code.md shape: a single block that is
    /// the whole document. No safe cut exists; return full length so the
    /// renderer treats it as one chunk rather than splitting mid-structure.
    @Test("Single giant block returns full length (no safe cut)")
    func singleGiantBlockNoSafeCut() {
        let bigCode = (1...2_000).map { "let x\($0) = \($0)" }.joined(separator: "\n")
        let text = """
        ```swift
        \(bigCode)
        ```
        """
        // Target size is much smaller than the block — but the block IS the
        // document. No boundary past target exists before the block ends.
        // Either we return at the end of the (single) block, which is
        // text.count, or we recognise no cut and return text.count directly.
        let end = MarkdownChunker.findFirstChunkEnd(in: text, targetSize: 1_000)
        #expect(end == text.count,
                "Single-block doc should return full length (got \(end), expected \(text.count))")
    }

    @Test("Cut lands on a top-level block boundary even when blocks are small")
    func cutsAtBlockBoundaryForManySmallBlocks() {
        // A series of small paragraphs — cut should land cleanly between two
        // of them, not inside one.
        let paragraphs = (1...100).map { "Paragraph number \($0) with a sentence." }
            .joined(separator: "\n\n")
        let text = paragraphs

        let end = MarkdownChunker.findFirstChunkEnd(in: text, targetSize: 500)

        // The cut must not land inside a paragraph — prefix should end on
        // whitespace (blank line) or be the whole doc.
        if end < text.count {
            let prefix = String(text.prefix(end))
            // Last non-empty char of prefix should be the end of a sentence.
            let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(trimmed.hasSuffix("."),
                    "Cut should land at end of a paragraph; prefix ends with: '\(trimmed.suffix(20))'")
        }
    }
}
