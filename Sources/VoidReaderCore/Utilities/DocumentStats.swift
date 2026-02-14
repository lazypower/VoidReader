import Foundation

/// Statistics about a document's content.
public struct DocumentStats: Equatable {
    public let wordCount: Int
    public let characterCount: Int
    public let characterCountNoSpaces: Int
    public let lineCount: Int
    public let readingTimeMinutes: Int

    public init(text: String) {
        // Character counts
        self.characterCount = text.count
        self.characterCountNoSpaces = text.filter { !$0.isWhitespace }.count

        // Line count
        self.lineCount = text.isEmpty ? 0 : text.components(separatedBy: .newlines).count

        // Word count - split on whitespace and newlines, filter empty
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        self.wordCount = words.count

        // Reading time at ~200 words per minute, minimum 1 minute if there's content
        if wordCount > 0 {
            self.readingTimeMinutes = max(1, Int(ceil(Double(wordCount) / 200.0)))
        } else {
            self.readingTimeMinutes = 0
        }
    }

    /// Creates stats for a text selection.
    public static func forSelection(_ text: String) -> DocumentStats {
        DocumentStats(text: text)
    }

    /// Formatted reading time string.
    public var readingTimeFormatted: String {
        if readingTimeMinutes == 0 {
            return "0 min read"
        } else if readingTimeMinutes == 1 {
            return "1 min read"
        } else {
            return "\(readingTimeMinutes) min read"
        }
    }

    /// Formatted word count string.
    public var wordCountFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: wordCount)) ?? "\(wordCount)") words"
    }

    /// Formatted character count string.
    public var characterCountFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "\(formatter.string(from: NSNumber(value: characterCount)) ?? "\(characterCount)") characters"
    }
}
