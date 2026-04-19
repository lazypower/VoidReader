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
    ///   - useRegex: Whether to treat the query as a regular expression
    /// - Returns: Array of matches
    public static func findMatches(
        query: String,
        in text: String,
        caseSensitive: Bool = false,
        useRegex: Bool = false
    ) -> [Match] {
        guard !query.isEmpty else { return [] }

        if useRegex {
            return findRegexMatches(query: query, in: text, caseSensitive: caseSensitive)
        }

        // Search directly on `text` with `.caseInsensitive` when needed. This
        // avoids allocating a lowercased copy and the subsequent distance/
        // offsetBy round-trip (each O(N)) that the previous implementation
        // did per match — the returned range is already valid on `text`.
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]

        var matches: [Match] = []
        var searchStart = text.startIndex
        var lineCursor = LineNumberCursor(text: text)

        while let range = text.range(of: query, options: options, range: searchStart..<text.endIndex) {
            let lineNumber = lineCursor.advance(to: range.lowerBound)
            matches.append(Match(range: range, lineNumber: lineNumber))
            searchStart = range.upperBound
        }

        return matches
    }

    /// Finds matches using regular expression.
    private static func findRegexMatches(
        query: String,
        in text: String,
        caseSensitive: Bool
    ) -> [Match] {
        var options: NSRegularExpression.Options = []
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }

        guard let regex = try? NSRegularExpression(pattern: query, options: options) else {
            return [] // Invalid regex, return no matches
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let results = regex.matches(in: text, options: [], range: nsRange)

        // Same trick as the literal path: walk a cursor through `text` once,
        // not once per match. Matches are returned in ascending order, so a
        // single forward pass suffices.
        var lineCursor = LineNumberCursor(text: text)
        return results.compactMap { result in
            guard let range = Range(result.range, in: text) else { return nil }
            let lineNumber = lineCursor.advance(to: range.lowerBound)
            return Match(range: range, lineNumber: lineNumber)
        }
    }

    /// Streams forward through `text`, counting newlines incrementally so each
    /// match pays O(distance-from-last-match) instead of O(N-from-start).
    /// Callers must advance monotonically — matches in ascending order.
    private struct LineNumberCursor {
        let text: String
        private var cursor: String.Index
        private var line: Int = 1

        init(text: String) {
            self.text = text
            self.cursor = text.startIndex
        }

        /// Advances the cursor to `target` (must be >= current cursor) and
        /// returns the 1-based line number at that position.
        mutating func advance(to target: String.Index) -> Int {
            if target > cursor {
                var i = cursor
                while i < target {
                    if text[i] == "\n" { line += 1 }
                    i = text.index(after: i)
                }
                cursor = target
            }
            return line
        }
    }

    /// Returns the text with the current match highlighted using markers.
    /// Useful for creating highlighted AttributedStrings.
    public static func highlightedRanges(
        query: String,
        in text: String,
        caseSensitive: Bool = false,
        useRegex: Bool = false
    ) -> [(Range<String.Index>, Bool)] {
        let matches = findMatches(query: query, in: text, caseSensitive: caseSensitive, useRegex: useRegex)
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
