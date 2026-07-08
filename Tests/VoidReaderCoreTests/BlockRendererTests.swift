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

    // §4.6 — blockquote paragraph separation and styled links

    @Test("Two-paragraph blockquote does not fuse its paragraphs")
    func blockquoteParagraphsSeparated() {
        let markdown = "> para1\n>\n> para2"
        let text = BlockRenderer.render(markdown).compactMap { block -> String? in
            if case .text(let attr) = block { return String(attr.characters) } else { return nil }
        }.joined(separator: "\n")
        #expect(text.contains("para1"))
        #expect(text.contains("para2"))
        #expect(!text.contains("para1para2"))
    }

    @Test("Bold text inside a link keeps the link attribute")
    func styledLinkKeepsLink() {
        let blocks = BlockRenderer.render("See [**bold**](https://example.com) here")
        var boldHasLink = false
        for block in blocks {
            if case .text(let attr) = block {
                for run in attr.runs where run.link != nil {
                    if String(attr[run.range].characters).contains("bold") { boldHasLink = true }
                }
            }
        }
        #expect(boldHasLink)
    }

    // §4.4 — raw HTML is preserved rather than silently dropped

    private func joinedText(_ blocks: [MarkdownBlock]) -> String {
        blocks.compactMap { block -> String? in
            if case .text(let attr) = block { return String(attr.characters) } else { return nil }
        }.joined(separator: "\n")
    }

    @Test("Inline HTML tags render verbatim instead of vanishing")
    func inlineHTMLPreserved() {
        let text = joinedText(BlockRenderer.render("Press <kbd>Cmd</kbd> now"))
        #expect(text.contains("<kbd>"))
        #expect(text.contains("Cmd"))
    }

    @Test("Inline <br> becomes a newline")
    func inlineBreakBecomesNewline() {
        let text = joinedText(BlockRenderer.render("line1<br>line2"))
        #expect(text.contains("line1"))
        #expect(text.contains("line2"))
        #expect(!text.contains("<br>"))
    }

    @Test("Block-level HTML survives as a code block")
    func blockHTMLPreserved() {
        let blocks = BlockRenderer.render("<details>\n<summary>More</summary>\ndetail\n</details>")
        let code = blocks.compactMap { block -> String? in
            if case .codeBlock(let data) = block { return data.code } else { return nil }
        }.joined()
        #expect(code.contains("summary"))
    }

    @Test("Inline HTML in a table cell is preserved")
    func inlineHTMLInTableCell() {
        let md = "| Key | Value |\n| --- | --- |\n| Shortcut | <kbd>Cmd</kbd> |"
        var found = false
        for block in BlockRenderer.render(md) {
            if case .table(let data) = block {
                for row in data.rows {
                    for cell in row where String(cell.content.characters).contains("<kbd>") { found = true }
                }
            }
        }
        #expect(found)
    }

    @Test("A very large HTML block is segmented, not one tall row")
    func largeHTMLBlockSegmented() {
        let body = Array(repeating: "<span>x</span>", count: 900).joined(separator: "\n")
        let blocks = BlockRenderer.render("<div>\n\(body)\n</div>")
        let codeBlocks = blocks.filter { if case .codeBlock = $0 { return true }; return false }
        #expect(codeBlocks.count > 1)
    }

    @Test("HTML comments are dropped, not shown")
    func htmlCommentDropped() {
        let blocks = BlockRenderer.render("<!-- secret note -->")
        let showsSecret = blocks.contains { block in
            switch block {
            case .codeBlock(let d): return d.code.contains("secret")
            case .text(let a): return String(a.characters).contains("secret")
            default: return false
            }
        }
        #expect(!showsSecret)
    }

    @Test("Blockquote paragraph after a list is separated, not fused")
    func blockquoteParagraphAfterList() {
        let markdown = "> - item\n>\n> para"
        let text = BlockRenderer.render(markdown).compactMap { block -> String? in
            if case .text(let attr) = block { return String(attr.characters) } else { return nil }
        }.joined(separator: "\n")
        #expect(text.contains("item"))
        #expect(text.contains("para"))
        #expect(!text.contains("itempara"))
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
