import Testing
@testable import VoidReaderCore

// Recovered from the old MarkdownRendererTests.swift, which also hosted these
// live BlockRenderer/MarkdownParser suites alongside the (now-deleted) tests for
// the dead AttributedString renderer.

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
