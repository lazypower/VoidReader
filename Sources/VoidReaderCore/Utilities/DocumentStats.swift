import Foundation

/// Statistics about a document's content.
public struct DocumentStats: Equatable {
    public let wordCount: Int
    public let characterCount: Int
    public let characterCountNoSpaces: Int
    public let lineCount: Int
    public let readingTimeMinutes: Int

    public init(text: String) {
        // For very large documents, use fast estimation instead of expensive string ops
        if text.count > 100_000 {
            self.characterCount = text.count
            // Estimate: assume ~15% whitespace (typical for prose)
            self.characterCountNoSpaces = Int(Double(text.count) * 0.85)
            // Count newlines efficiently with a simple loop
            var newlineCount = 0
            for char in text where char == "\n" {
                newlineCount += 1
            }
            self.lineCount = text.isEmpty ? 0 : newlineCount + 1
            // Estimate: ~5 chars per word average
            self.wordCount = text.count / 5
            self.readingTimeMinutes = max(1, self.wordCount / 200)
            return
        }

        // For normal documents, compute exact stats
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
