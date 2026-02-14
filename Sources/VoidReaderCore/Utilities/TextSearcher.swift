import Foundation

/// Manages text search within a document.
public struct TextSearcher {
    /// A match found in the document.
    public struct Match: Equatable {
        public let range: Range<String.Index>
        public let lineNumber: Int

        public init(range: Range<String.Index>, lineNumber: Int) {
            self.range = range
            self.lineNumber = lineNumber
        }
    }

    /// Finds all occurrences of a search term in the given text.
    /// - Parameters:
    ///   - query: The search term
    ///   - text: The text to search in
    ///   - caseSensitive: Whether the search is case-sensitive
    /// - Returns: Array of matches
    public static func findMatches(
        query: String,
        in text: String,
        caseSensitive: Bool = false
    ) -> [Match] {
        guard !query.isEmpty else { return [] }

        var matches: [Match] = []
        let searchText = caseSensitive ? text : text.lowercased()
        let searchQuery = caseSensitive ? query : query.lowercased()

        var searchStart = text.startIndex
        while let range = searchText.range(of: searchQuery, range: searchStart..<searchText.endIndex) {
            // Calculate line number
            let lineNumber = text[..<range.lowerBound].filter { $0 == "\n" }.count + 1

            // Map range back to original text
            let originalRange = text.index(text.startIndex, offsetBy: text.distance(from: text.startIndex, to: range.lowerBound))..<text.index(text.startIndex, offsetBy: text.distance(from: text.startIndex, to: range.upperBound))

            matches.append(Match(range: originalRange, lineNumber: lineNumber))

            // Move past this match
            searchStart = range.upperBound
        }

        return matches
    }

    /// Returns the text with the current match highlighted using markers.
    /// Useful for creating highlighted AttributedStrings.
    public static func highlightedRanges(
        query: String,
        in text: String,
        caseSensitive: Bool = false
    ) -> [(Range<String.Index>, Bool)] {
        let matches = findMatches(query: query, in: text, caseSensitive: caseSensitive)
        guard !matches.isEmpty else {
            return [(text.startIndex..<text.endIndex, false)]
        }

        var ranges: [(Range<String.Index>, Bool)] = []
        var currentIndex = text.startIndex

        for match in matches {
            // Add non-matching range before this match
            if currentIndex < match.range.lowerBound {
                ranges.append((currentIndex..<match.range.lowerBound, false))
            }

            // Add the match
            ranges.append((match.range, true))

            currentIndex = match.range.upperBound
        }

        // Add remaining non-matching text
        if currentIndex < text.endIndex {
            ranges.append((currentIndex..<text.endIndex, false))
        }

        return ranges
    }
}
