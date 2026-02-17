import Foundation
import Markdown

/// Protocol for lint rules that check markdown documents.
public protocol LintRule {
    /// Unique identifier for this rule (e.g., "MD001").
    var id: String { get }

    /// Human-readable description of what this rule checks.
    var description: String { get }

    /// Checks the document and returns any warnings.
    /// - Parameters:
    ///   - document: The parsed markdown document
    ///   - source: The original source text
    /// - Returns: Array of warnings found
    func check(document: Document, source: String) -> [LintWarning]
}

// MARK: - Source Line Utilities

/// Helper for working with source text lines.
public struct SourceLines {
    private let lines: [Substring]
    private let lineStarts: [String.Index]

    public init(_ source: String) {
        var lines: [Substring] = []
        var lineStarts: [String.Index] = []
        var currentIndex = source.startIndex

        while currentIndex < source.endIndex {
            lineStarts.append(currentIndex)
            if let newlineIndex = source[currentIndex...].firstIndex(of: "\n") {
                lines.append(source[currentIndex..<newlineIndex])
                currentIndex = source.index(after: newlineIndex)
            } else {
                lines.append(source[currentIndex...])
                break
            }
        }

        // Handle empty string or trailing newline
        if source.isEmpty || source.last == "\n" {
            lineStarts.append(source.endIndex)
            lines.append("")
        }

        self.lines = lines
        self.lineStarts = lineStarts
    }

    /// Number of lines.
    public var count: Int { lines.count }

    /// Get line at index (0-based).
    public subscript(index: Int) -> Substring {
        guard index >= 0 && index < lines.count else { return "" }
        return lines[index]
    }

    /// Get line number (1-based) for a character index.
    public func lineNumber(for index: String.Index, in source: String) -> Int {
        for (lineIndex, start) in lineStarts.enumerated().reversed() {
            if index >= start {
                return lineIndex + 1
            }
        }
        return 1
    }

    /// All lines as array of strings.
    public var allLines: [String] {
        lines.map(String.init)
    }
}
