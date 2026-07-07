import Testing
@testable import VoidReaderCore

/// Covers the fence-aware `$$` extraction (§4.1) and document-start-only
/// frontmatter recognition (§4.2) at the BlockRenderer.render level.
@Suite("Math extraction & chunk rendering")
struct MathAndChunkRenderTests {

    private func hasMathBlock(_ blocks: [MarkdownBlock]) -> Bool {
        blocks.contains { if case .mathBlock = $0 { return true } else { return false } }
    }
    private func hasCodeBlock(_ blocks: [MarkdownBlock]) -> Bool {
        blocks.contains { if case .codeBlock = $0 { return true } else { return false } }
    }
    private func hasFrontmatter(_ blocks: [MarkdownBlock]) -> Bool {
        blocks.contains { if case .frontmatter = $0 { return true } else { return false } }
    }

    // MARK: - §4.1 fence-aware math

    @Test("$$ inside a fenced code block is not torn out as math")
    func fencedDollarsStayCode() {
        let md = """
        Intro paragraph.

        ```bash
        echo $$      # the shell PID
        kill -9 $$
        ```

        End paragraph.
        """
        let blocks = BlockRenderer.render(md)
        #expect(!hasMathBlock(blocks))
        #expect(hasCodeBlock(blocks))
    }

    @Test("Real $$ outside fences still becomes a math block")
    func realBlockMathExtracted() {
        let blocks = BlockRenderer.render("Before text\n\n$$E = mc^2$$\n\nAfter text")
        let math = blocks.compactMap { block -> String? in
            if case .mathBlock(let data) = block { return data.latex } else { return nil }
        }
        #expect(math == ["E = mc^2"])
    }

    @Test("Math after a fence still renders while the fence stays intact")
    func mathAfterFenceCoexists() {
        let md = """
        ```sh
        x=$$
        ```

        $$a + b$$
        """
        let blocks = BlockRenderer.render(md)
        #expect(hasCodeBlock(blocks))
        #expect(hasMathBlock(blocks))
    }

    // MARK: - §4.2 frontmatter only at document start

    @Test("Leading --- in a mid-document chunk is not frontmatter")
    func frontmatterOnlyAtDocumentStart() {
        let chunk = """
        ---
        Some: intro line
        More prose here
        ---
        Body after
        """
        // As the true document start, this is frontmatter.
        #expect(hasFrontmatter(BlockRenderer.render(chunk, isDocumentStart: true)))
        // As a background chunk, the leading --- is a thematic break, not a fence.
        #expect(!hasFrontmatter(BlockRenderer.render(chunk, isDocumentStart: false)))
    }
}
