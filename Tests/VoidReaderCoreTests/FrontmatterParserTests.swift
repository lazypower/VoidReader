import Testing
@testable import VoidReaderCore

@Suite("Frontmatter Parser")
struct FrontmatterParserTests {

    @Test("Extracts simple key-value frontmatter")
    func simpleExtraction() {
        let input = """
        ---
        title: Hello World
        author: Test
        ---

        # Content here
        """
        let result = FrontmatterParser.parse(input)
        #expect(result.frontmatter != nil)
        #expect(result.frontmatter?.fields.count == 2)
        #expect(result.frontmatter?.value(for: "title") == "Hello World")
        #expect(result.frontmatter?.value(for: "author") == "Test")
        #expect(result.body.contains("# Content here"))
        #expect(!result.body.contains("---"))
    }

    @Test("Returns nil frontmatter for documents without it")
    func noFrontmatter() {
        let input = "# Just a heading\n\nSome text."
        let result = FrontmatterParser.parse(input)
        #expect(result.frontmatter == nil)
        #expect(result.body == input)
    }

    @Test("Returns nil for unclosed frontmatter fence")
    func unclosedFence() {
        let input = """
        ---
        title: Orphan
        author: Nobody

        # Content starts without closing fence
        """
        let result = FrontmatterParser.parse(input)
        #expect(result.frontmatter == nil)
    }

    @Test("Returns nil for empty frontmatter block")
    func emptyBlock() {
        let input = """
        ---
        ---
        # Content
        """
        let result = FrontmatterParser.parse(input)
        #expect(result.frontmatter == nil)
    }

    @Test("Preserves field order")
    func fieldOrder() {
        let input = """
        ---
        zebra: last
        alpha: first
        middle: middle
        ---
        Body
        """
        let result = FrontmatterParser.parse(input)
        let keys = result.frontmatter?.fields.map(\.key)
        #expect(keys == ["zebra", "alpha", "middle"])
    }

    @Test("Case-insensitive value lookup")
    func caseInsensitiveLookup() {
        let input = """
        ---
        Title: Hello
        ---
        Body
        """
        let result = FrontmatterParser.parse(input)
        #expect(result.frontmatter?.value(for: "title") == "Hello")
        #expect(result.frontmatter?.value(for: "TITLE") == "Hello")
        #expect(result.frontmatter?.value(for: "Title") == "Hello")
    }

    @Test("Handles values with colons")
    func valuesWithColons() {
        let input = """
        ---
        url: https://example.com:8080/path
        ---
        Body
        """
        let result = FrontmatterParser.parse(input)
        #expect(result.frontmatter?.value(for: "url") == "https://example.com:8080/path")
    }

    @Test("Frontmatter stripped before block rendering")
    func strippedFromBlockRenderer() {
        let input = """
        ---
        title: Test Doc
        tags: one, two, three
        ---

        # Actual Heading

        Body paragraph.
        """
        let blocks = BlockRenderer.render(input)
        // Should have a frontmatter block + text blocks, NOT raw --- in text
        let hasFrontmatterBlock = blocks.contains { block in
            if case .frontmatter = block { return true }
            return false
        }
        #expect(hasFrontmatterBlock, "BlockRenderer should produce a .frontmatter block")

        // No text block should contain "---" from the fences
        let textContents = blocks.compactMap { block -> String? in
            if case .text(let attr) = block { return String(attr.characters) }
            return nil
        }
        let hasFenceLeakage = textContents.contains { $0.contains("---") }
        #expect(!hasFenceLeakage, "Frontmatter fences should not leak into text blocks")
    }

    @Test("Document without frontmatter produces no frontmatter block")
    func noFrontmatterBlock() {
        let input = "# Just a heading\n\nSome text."
        let blocks = BlockRenderer.render(input)
        let hasFrontmatterBlock = blocks.contains { block in
            if case .frontmatter = block { return true }
            return false
        }
        #expect(!hasFrontmatterBlock)
    }
}
