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

    @Test("Renders strikethrough")
    func rendersStrikethrough() throws {
        let result = try MarkdownRenderer.render("This is ~~deleted~~ text")
        #expect(String(result.characters).contains("deleted"))
    }
}

@Suite("Block Renderer Tests")
struct BlockRendererTests {

    @Test("Renders tables")
    func rendersTables() {
        let markdown = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let blocks = BlockRenderer.render(markdown)
        let hasTable = blocks.contains { block in
            if case .table = block { return true }
            return false
        }
        #expect(hasTable)
    }

    @Test("Renders task lists")
    func rendersTaskLists() {
        let markdown = """
        - [x] Done
        - [ ] Todo
        """
        let blocks = BlockRenderer.render(markdown)
        let hasTaskList = blocks.contains { block in
            if case .taskList = block { return true }
            return false
        }
        #expect(hasTaskList)
    }

    @Test("Renders code blocks as separate blocks")
    func rendersCodeBlocks() {
        let markdown = """
        Some text

        ```swift
        let x = 1
        ```
        """
        let blocks = BlockRenderer.render(markdown)
        let hasCodeBlock = blocks.contains { block in
            if case .codeBlock = block { return true }
            return false
        }
        #expect(hasCodeBlock)
    }

    @Test("Renders standalone images as blocks")
    func rendersStandaloneImages() {
        let markdown = """
        Some text

        ![Alt text](image.png)

        More text
        """
        let blocks = BlockRenderer.render(markdown)
        let hasImage = blocks.contains { block in
            if case .image = block { return true }
            return false
        }
        #expect(hasImage)
    }

    @Test("Table has correct column count")
    func tableColumnCount() {
        let markdown = """
        | A | B | C |
        |---|---|---|
        | 1 | 2 | 3 |
        """
        let blocks = BlockRenderer.render(markdown)
        for block in blocks {
            if case .table(let data) = block {
                #expect(data.headers.count == 3)
                #expect(data.rows.first?.count == 3)
            }
        }
    }

    @Test("Task list tracks checked state")
    func taskListCheckedState() {
        let markdown = """
        - [x] Done
        - [ ] Todo
        """
        let blocks = BlockRenderer.render(markdown)
        for block in blocks {
            if case .taskList(let items) = block {
                #expect(items.count == 2)
                #expect(items[0].isChecked == true)
                #expect(items[1].isChecked == false)
            }
        }
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

    @Test("Handles empty document")
    func handlesEmptyDocument() {
        let doc = MarkdownParser.parse("")
        #expect(doc.childCount == 0)
    }

    @Test("Parses GFM tables")
    func parsesGFMTables() {
        let doc = MarkdownParser.parse("""
        | A | B |
        |---|---|
        | 1 | 2 |
        """)
        #expect(doc.childCount > 0)
    }
}
