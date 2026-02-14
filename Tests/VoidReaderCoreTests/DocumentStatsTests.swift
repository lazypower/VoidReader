import Testing
@testable import VoidReaderCore

@Suite("Document Stats Tests")
struct DocumentStatsTests {

    @Test("Counts words correctly")
    func countsWords() {
        let stats = DocumentStats(text: "Hello world, this is a test.")
        #expect(stats.wordCount == 6)
    }

    @Test("Counts words with multiple spaces")
    func countsWordsWithMultipleSpaces() {
        let stats = DocumentStats(text: "Hello    world")
        #expect(stats.wordCount == 2)
    }

    @Test("Counts words across newlines")
    func countsWordsAcrossNewlines() {
        let stats = DocumentStats(text: "Hello\nworld\n\ntest")
        #expect(stats.wordCount == 3)
    }

    @Test("Counts characters including spaces")
    func countsCharacters() {
        let stats = DocumentStats(text: "Hello world")
        #expect(stats.characterCount == 11)
    }

    @Test("Counts characters excluding spaces")
    func countsCharactersNoSpaces() {
        let stats = DocumentStats(text: "Hello world")
        #expect(stats.characterCountNoSpaces == 10)
    }

    @Test("Counts lines")
    func countsLines() {
        let stats = DocumentStats(text: "Line 1\nLine 2\nLine 3")
        #expect(stats.lineCount == 3)
    }

    @Test("Calculates reading time")
    func calculatesReadingTime() {
        // 200 words = 1 minute
        let words200 = Array(repeating: "word", count: 200).joined(separator: " ")
        let stats = DocumentStats(text: words200)
        #expect(stats.readingTimeMinutes == 1)
    }

    @Test("Reading time rounds up")
    func readingTimeRoundsUp() {
        // 201 words = 2 minutes (rounds up)
        let words201 = Array(repeating: "word", count: 201).joined(separator: " ")
        let stats = DocumentStats(text: words201)
        #expect(stats.readingTimeMinutes == 2)
    }

    @Test("Minimum reading time is 1 for non-empty")
    func minimumReadingTime() {
        let stats = DocumentStats(text: "Hello")
        #expect(stats.readingTimeMinutes == 1)
    }

    @Test("Empty text has zero stats")
    func emptyText() {
        let stats = DocumentStats(text: "")
        #expect(stats.wordCount == 0)
        #expect(stats.characterCount == 0)
        #expect(stats.lineCount == 0)
        #expect(stats.readingTimeMinutes == 0)
    }

    @Test("Formats word count with commas")
    func formatsWordCount() {
        let words = Array(repeating: "word", count: 1500).joined(separator: " ")
        let stats = DocumentStats(text: words)
        #expect(stats.wordCountFormatted.contains("1,500") || stats.wordCountFormatted.contains("1500"))
    }

    @Test("Formats reading time singular")
    func formatsReadingTimeSingular() {
        let stats = DocumentStats(text: "Hello world")
        #expect(stats.readingTimeFormatted == "1 min read")
    }

    @Test("Formats reading time plural")
    func formatsReadingTimePlural() {
        let words = Array(repeating: "word", count: 500).joined(separator: " ")
        let stats = DocumentStats(text: words)
        #expect(stats.readingTimeFormatted == "3 min read")
    }
}
