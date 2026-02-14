import Testing
import Foundation
@testable import VoidReaderCore

@Suite("Markdown Performance Tests")
struct MarkdownPerformanceTests {

    /// Generates a large markdown document with various element types.
    private func generateLargeDocument(paragraphs: Int = 100) -> String {
        var sections: [String] = []

        for i in 1...paragraphs {
            // Add a heading every 10 paragraphs
            if i % 10 == 1 {
                sections.append("## Section \(i / 10 + 1)")
            }

            // Regular paragraph with formatting
            sections.append("""
            This is paragraph \(i) with **bold text**, *italic text*, and `inline code`.
            It also has a [link](https://example.com/\(i)) and some more content to make it realistic.
            """)

            // Add a list every 5 paragraphs
            if i % 5 == 0 {
                sections.append("""
                - List item one
                - List item two with **bold**
                - List item three with `code`
                """)
            }

            // Add a code block every 15 paragraphs
            if i % 15 == 0 {
                sections.append("""
                ```swift
                func example\(i)() {
                    let value = \(i)
                    print("Value: \\(value)")
                }
                ```
                """)
            }

            // Add a blockquote every 20 paragraphs
            if i % 20 == 0 {
                sections.append("> This is a blockquote in section \(i). It contains *emphasized* text.")
            }

            // Add a task list every 25 paragraphs
            if i % 25 == 0 {
                sections.append("""
                - [x] Completed task \(i)
                - [ ] Pending task \(i + 1)
                """)
            }

            // Add a table every 30 paragraphs
            if i % 30 == 0 {
                sections.append("""
                | Column A | Column B | Column C |
                |----------|:--------:|---------:|
                | Left \(i) | Center | Right |
                | Data | More | Values |
                """)
            }
        }

        return "# Large Document Test\n\n" + sections.joined(separator: "\n\n")
    }

    @Test("Parses large document within reasonable time")
    func parsesLargeDocument() {
        let document = generateLargeDocument(paragraphs: 200)

        // Verify document is substantial (200 paragraphs generates ~40KB)
        #expect(document.count > 30000, "Document should be at least 30KB")

        let startTime = Date()
        let parsed = MarkdownParser.parse(document)
        let parseTime = Date().timeIntervalSince(startTime)

        // Should parse in under 1 second
        #expect(parseTime < 1.0, "Parsing took \(parseTime)s, should be under 1s")
        #expect(parsed.childCount > 0, "Document should have content")
    }

    @Test("Renders large document within reasonable time")
    func rendersLargeDocument() throws {
        let document = generateLargeDocument(paragraphs: 200)

        let startTime = Date()
        let result = try MarkdownRenderer.render(document)
        let renderTime = Date().timeIntervalSince(startTime)

        // Should render in under 2 seconds
        #expect(renderTime < 2.0, "Rendering took \(renderTime)s, should be under 2s")
        #expect(!result.characters.isEmpty, "Result should have content")
    }

    @Test("Block renderer handles large document")
    func blockRendererLargeDocument() {
        let document = generateLargeDocument(paragraphs: 200)

        let startTime = Date()
        let blocks = BlockRenderer.render(document)
        let renderTime = Date().timeIntervalSince(startTime)

        // Should render in under 2 seconds
        #expect(renderTime < 2.0, "Block rendering took \(renderTime)s, should be under 2s")
        #expect(!blocks.isEmpty, "Should have blocks")

        // Verify we got various block types
        let hasText = blocks.contains { if case .text = $0 { return true }; return false }
        let hasCode = blocks.contains { if case .codeBlock = $0 { return true }; return false }
        let hasTasks = blocks.contains { if case .taskList = $0 { return true }; return false }
        let hasTables = blocks.contains { if case .table = $0 { return true }; return false }

        #expect(hasText, "Should have text blocks")
        #expect(hasCode, "Should have code blocks")
        #expect(hasTasks, "Should have task lists")
        #expect(hasTables, "Should have tables")
    }

    @Test("Handles very long lines")
    func handlesVeryLongLines() throws {
        // Create a paragraph with a very long line
        let longLine = String(repeating: "word ", count: 1000)
        let document = """
        # Long Line Test

        \(longLine)

        Another normal paragraph.
        """

        let result = try MarkdownRenderer.render(document)
        #expect(String(result.characters).contains("word"))
    }

    @Test("Handles deeply nested lists")
    func handlesDeeplyNestedLists() throws {
        var nested = ""
        for i in 0..<10 {
            nested += String(repeating: "  ", count: i) + "- Level \(i)\n"
        }

        let document = """
        # Nested List Test

        \(nested)
        """

        let result = try MarkdownRenderer.render(document)
        #expect(String(result.characters).contains("Level 0"))
        #expect(String(result.characters).contains("Level 9"))
    }
}
