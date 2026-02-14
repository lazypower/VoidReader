import Testing
@testable import VoidReaderCore

@Suite("Heading Extraction Tests")
struct HeadingExtractionTests {

    // MARK: - Basic Extraction

    @Test("Extracts single heading")
    func extractsSingleHeading() {
        let text = "# Hello World"
        let doc = MarkdownParser.parse(text)
        let headings = MarkdownParser.extractHeadings(from: doc)

        #expect(headings.count == 1)
        #expect(headings[0].level == 1)
        #expect(headings[0].text == "Hello World")
    }

    @Test("Extracts multiple headings")
    func extractsMultipleHeadings() {
        let text = """
        # First
        ## Second
        ### Third
        """
        let doc = MarkdownParser.parse(text)
        let headings = MarkdownParser.extractHeadings(from: doc)

        #expect(headings.count == 3)
    }

    @Test("Extracts all heading levels")
    func extractsAllLevels() {
        let text = """
        # H1
        ## H2
        ### H3
        #### H4
        ##### H5
        ###### H6
        """
        let doc = MarkdownParser.parse(text)
        let headings = MarkdownParser.extractHeadings(from: doc)

        #expect(headings.count == 6)
        #expect(headings[0].level == 1)
        #expect(headings[1].level == 2)
        #expect(headings[2].level == 3)
        #expect(headings[3].level == 4)
        #expect(headings[4].level == 5)
        #expect(headings[5].level == 6)
    }

    // MARK: - Heading Text

    @Test("Preserves heading text")
    func preservesHeadingText() {
        let text = """
        # Introduction
        ## Getting Started
        ### Installation Guide
        """
        let doc = MarkdownParser.parse(text)
        let headings = MarkdownParser.extractHeadings(from: doc)

        #expect(headings[0].text == "Introduction")
        #expect(headings[1].text == "Getting Started")
        #expect(headings[2].text == "Installation Guide")
    }

    @Test("Handles heading with inline formatting")
    func handlesInlineFormatting() {
        let text = "# Hello **bold** world"
        let doc = MarkdownParser.parse(text)
        let headings = MarkdownParser.extractHeadings(from: doc)

        #expect(headings.count == 1)
        // Text should contain the words (formatting may be stripped)
        #expect(headings[0].text.contains("Hello"))
        #expect(headings[0].text.contains("world"))
    }

    // MARK: - Document Structure

    @Test("Maintains heading order")
    func maintainsOrder() {
        let text = """
        # First
        Some content here.

        ## Second

        More content.

        # Third
        """
        let doc = MarkdownParser.parse(text)
        let headings = MarkdownParser.extractHeadings(from: doc)

        #expect(headings.count == 3)
        #expect(headings[0].text == "First")
        #expect(headings[1].text == "Second")
        #expect(headings[2].text == "Third")
    }

    @Test("Returns empty for document without headings")
    func emptyForNoHeadings() {
        let text = """
        Just some text.

        - A list item
        - Another item

        More paragraphs.
        """
        let doc = MarkdownParser.parse(text)
        let headings = MarkdownParser.extractHeadings(from: doc)

        #expect(headings.isEmpty)
    }

    // MARK: - Edge Cases

    @Test("Handles empty document")
    func handlesEmptyDocument() {
        let text = ""
        let doc = MarkdownParser.parse(text)
        let headings = MarkdownParser.extractHeadings(from: doc)

        #expect(headings.isEmpty)
    }

    @Test("Handles ATX style headings only")
    func handlesAtxStyle() {
        let text = """
        # ATX Heading

        Regular paragraph
        """
        let doc = MarkdownParser.parse(text)
        let headings = MarkdownParser.extractHeadings(from: doc)

        #expect(headings.count == 1)
        #expect(headings[0].text == "ATX Heading")
    }

    @Test("Each heading has unique ID")
    func uniqueIDs() {
        let text = """
        # Same
        # Same
        # Same
        """
        let doc = MarkdownParser.parse(text)
        let headings = MarkdownParser.extractHeadings(from: doc)

        #expect(headings.count == 3)
        let ids = Set(headings.map { $0.id })
        #expect(ids.count == 3) // All unique
    }
}
