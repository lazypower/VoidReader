import Testing
@testable import VoidReaderCore

@Suite("Text Searcher Tests")
struct TextSearcherTests {

    // MARK: - Basic Find

    @Test("Finds single match")
    func findsSingleMatch() {
        let text = "Hello world"
        let matches = TextSearcher.findMatches(query: "world", in: text)
        #expect(matches.count == 1)
        #expect(String(text[matches[0].range]) == "world")
    }

    @Test("Finds multiple matches")
    func findsMultipleMatches() {
        let text = "The cat sat on the mat with another cat"
        let matches = TextSearcher.findMatches(query: "cat", in: text)
        #expect(matches.count == 2)
    }

    @Test("Returns empty array for no matches")
    func noMatchesReturnsEmpty() {
        let text = "Hello world"
        let matches = TextSearcher.findMatches(query: "xyz", in: text)
        #expect(matches.isEmpty)
    }

    @Test("Returns empty for empty query")
    func emptyQueryReturnsEmpty() {
        let text = "Hello world"
        let matches = TextSearcher.findMatches(query: "", in: text)
        #expect(matches.isEmpty)
    }

    // MARK: - Case Sensitivity

    @Test("Case insensitive by default")
    func caseInsensitiveByDefault() {
        let text = "Hello HELLO hello"
        let matches = TextSearcher.findMatches(query: "hello", in: text)
        #expect(matches.count == 3)
    }

    @Test("Case sensitive when requested")
    func caseSensitiveWhenRequested() {
        let text = "Hello HELLO hello"
        let matches = TextSearcher.findMatches(query: "hello", in: text, caseSensitive: true)
        #expect(matches.count == 1)
    }

    @Test("Case sensitive matches exact case")
    func caseSensitiveMatchesExact() {
        let text = "Hello HELLO hello"
        let matches = TextSearcher.findMatches(query: "HELLO", in: text, caseSensitive: true)
        #expect(matches.count == 1)
        #expect(String(text[matches[0].range]) == "HELLO")
    }

    // MARK: - Line Numbers

    @Test("Reports correct line numbers")
    func reportsCorrectLineNumbers() {
        let text = """
        Line one
        Line two with target
        Line three
        Another target here
        """
        let matches = TextSearcher.findMatches(query: "target", in: text)
        #expect(matches.count == 2)
        #expect(matches[0].lineNumber == 2)
        #expect(matches[1].lineNumber == 4)
    }

    @Test("First line is line 1")
    func firstLineIsOne() {
        let text = "target on first line"
        let matches = TextSearcher.findMatches(query: "target", in: text)
        #expect(matches.count == 1)
        #expect(matches[0].lineNumber == 1)
    }

    // MARK: - Edge Cases

    @Test("Finds overlapping potential matches correctly")
    func findsNonOverlappingMatches() {
        let text = "aaaa"
        let matches = TextSearcher.findMatches(query: "aa", in: text)
        // Should find "aa" at positions 0 and 2 (non-overlapping)
        #expect(matches.count == 2)
    }

    @Test("Handles special characters in query")
    func handlesSpecialCharacters() {
        let text = "Price is $100.00"
        let matches = TextSearcher.findMatches(query: "$100", in: text)
        #expect(matches.count == 1)
    }

    @Test("Handles unicode characters")
    func handlesUnicode() {
        let text = "Hello 世界 world 世界"
        let matches = TextSearcher.findMatches(query: "世界", in: text)
        #expect(matches.count == 2)
    }

    // MARK: - Highlighted Ranges

    @Test("Highlighted ranges covers full text")
    func highlightedRangesCoversFull() {
        let text = "Hello world"
        let ranges = TextSearcher.highlightedRanges(query: "world", in: text)

        // Should have: "Hello " (not highlighted) + "world" (highlighted)
        #expect(ranges.count == 2)
        #expect(ranges[0].1 == false) // "Hello " not highlighted
        #expect(ranges[1].1 == true)  // "world" highlighted
    }

    @Test("No matches returns single non-highlighted range")
    func noMatchesSingleRange() {
        let text = "Hello world"
        let ranges = TextSearcher.highlightedRanges(query: "xyz", in: text)
        #expect(ranges.count == 1)
        #expect(ranges[0].1 == false)
    }

    // MARK: - Regex Search

    @Test("Regex finds simple pattern")
    func regexFindsSimplePattern() {
        let text = "cat bat rat sat"
        let matches = TextSearcher.findMatches(query: "[cbrs]at", in: text, useRegex: true)
        #expect(matches.count == 4)
    }

    @Test("Regex finds digit patterns")
    func regexFindsDigits() {
        let text = "Order 123 and order 456"
        let matches = TextSearcher.findMatches(query: "\\d+", in: text, useRegex: true)
        #expect(matches.count == 2)
        #expect(String(text[matches[0].range]) == "123")
        #expect(String(text[matches[1].range]) == "456")
    }

    @Test("Regex respects case sensitivity")
    func regexRespectsCaseSensitivity() {
        let text = "Hello HELLO hello"
        let matchesInsensitive = TextSearcher.findMatches(
            query: "hello",
            in: text,
            caseSensitive: false,
            useRegex: true
        )
        #expect(matchesInsensitive.count == 3)

        let matchesSensitive = TextSearcher.findMatches(
            query: "hello",
            in: text,
            caseSensitive: true,
            useRegex: true
        )
        #expect(matchesSensitive.count == 1)
    }

    @Test("Invalid regex returns no matches")
    func invalidRegexReturnsEmpty() {
        let text = "Hello world"
        let matches = TextSearcher.findMatches(query: "[invalid", in: text, useRegex: true)
        #expect(matches.isEmpty)
    }

    @Test("Regex with groups")
    func regexWithGroups() {
        let text = "email@example.com and test@test.org"
        let matches = TextSearcher.findMatches(
            query: "\\w+@\\w+\\.\\w+",
            in: text,
            useRegex: true
        )
        #expect(matches.count == 2)
    }

    @Test("Regex word boundaries")
    func regexWordBoundaries() {
        let text = "cat catalog caterpillar"
        let matches = TextSearcher.findMatches(query: "\\bcat\\b", in: text, useRegex: true)
        #expect(matches.count == 1)
        #expect(String(text[matches[0].range]) == "cat")
    }
}
