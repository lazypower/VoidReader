import Testing
@testable import VoidReaderCore

@Suite("Markdown Renderer Tests")
struct MarkdownRendererTests {

    @Test("Renders plain text")
    func rendersPlainText() throws {
        let result = try MarkdownRenderer.render("Hello, World!")
        #expect(String(result.characters).contains("Hello, World!"))
    }

    @Test("Renders heading with larger font")
    func rendersHeading() throws {
        let result = try MarkdownRenderer.render("# Big Heading")
        #expect(String(result.characters).contains("Big Heading"))
    }

    @Test("Renders multiple heading levels")
    func rendersHeadingLevels() throws {
        let markdown = """
        # H1
        ## H2
        ### H3
        """
        let result = try MarkdownRenderer.render(markdown)
        let text = String(result.characters)
        #expect(text.contains("H1"))
        #expect(text.contains("H2"))
        #expect(text.contains("H3"))
    }

    @Test("Renders bold text")
    func rendersBoldText() throws {
        let result = try MarkdownRenderer.render("This is **bold** text")
        #expect(String(result.characters).contains("bold"))
    }

    @Test("Renders italic text")
    func rendersItalicText() throws {
        let result = try MarkdownRenderer.render("This is *italic* text")
        #expect(String(result.characters).contains("italic"))
    }

    @Test("Renders inline code")
    func rendersInlineCode() throws {
        let result = try MarkdownRenderer.render("Use `let x = 1` here")
        #expect(String(result.characters).contains("let x = 1"))
    }

    @Test("Renders code block")
    func rendersCodeBlock() throws {
        let markdown = """
        ```swift
        let greeting = "Hello"
        ```
        """
        let result = try MarkdownRenderer.render(markdown)
        #expect(String(result.characters).contains("let greeting"))
    }

    @Test("Renders unordered list")
    func rendersUnorderedList() throws {
        let markdown = """
        - Item one
        - Item two
        - Item three
        """
        let result = try MarkdownRenderer.render(markdown)
        let text = String(result.characters)
        #expect(text.contains("•"))
        #expect(text.contains("Item one"))
        #expect(text.contains("Item two"))
    }

    @Test("Renders ordered list")
    func rendersOrderedList() throws {
        let markdown = """
        1. First
        2. Second
        3. Third
        """
        let result = try MarkdownRenderer.render(markdown)
        let text = String(result.characters)
        #expect(text.contains("1."))
        #expect(text.contains("First"))
    }

    @Test("Renders blockquote")
    func rendersBlockquote() throws {
        let result = try MarkdownRenderer.render("> This is a quote")
        let text = String(result.characters)
        #expect(text.contains("│"))
        #expect(text.contains("This is a quote"))
    }

    @Test("Renders links")
    func rendersLinks() throws {
        let result = try MarkdownRenderer.render("[Click here](https://example.com)")
        #expect(String(result.characters).contains("Click here"))
    }

    @Test("Renders horizontal rule")
    func rendersHorizontalRule() throws {
        let result = try MarkdownRenderer.render("Above\n\n---\n\nBelow")
        let text = String(result.characters)
        #expect(text.contains("───"))
    }

    @Test("Handles empty input")
    func handlesEmptyInput() throws {
        let result = try MarkdownRenderer.render("")
        #expect(result.characters.isEmpty)
    }

    @Test("Handles complex nested formatting")
    func handlesNestedFormatting() throws {
        let result = try MarkdownRenderer.render("This is ***bold and italic*** text")
        #expect(String(result.characters).contains("bold and italic"))
    }
}

@Suite("Markdown Parser Tests")
struct MarkdownParserTests {

    @Test("Parses document")
    func parsesDocument() {
        let doc = MarkdownParser.parse("# Hello\n\nWorld")
        #expect(doc.childCount > 0)
    }

    @Test("Extracts headings")
    func extractsHeadings() {
        let doc = MarkdownParser.parse("""
        # First
        ## Second
        ### Third
        """)
        let headings = MarkdownParser.extractHeadings(from: doc)
        #expect(headings.count == 3)
        #expect(headings[0].level == 1)
        #expect(headings[0].text == "First")
        #expect(headings[1].level == 2)
        #expect(headings[2].level == 3)
    }
}
