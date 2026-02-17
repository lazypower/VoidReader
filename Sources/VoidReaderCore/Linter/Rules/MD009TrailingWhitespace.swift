import Foundation
import Markdown

/// MD009: Lines should not have trailing whitespace.
public struct MD009TrailingWhitespace: LintRule {
    public let id = "MD009"
    public let description = "No trailing whitespace"

    public init() {}

    public func check(document: Document, source: String) -> [LintWarning] {
        var warnings: [LintWarning] = []
        let lines = source.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            // Skip if line is empty
            guard !line.isEmpty else { continue }

            // Check for trailing whitespace (spaces or tabs)
            if let lastChar = line.last, lastChar.isWhitespace && lastChar != "\n" {
                // Count trailing whitespace
                let trimmed = line.trailingWhitespaceCount

                if trimmed > 0 {
                    // Exception: two trailing spaces for hard line breaks
                    if trimmed == 2 && line.hasSuffix("  ") {
                        continue
                    }

                    warnings.append(LintWarning(
                        line: index + 1,
                        column: line.count - trimmed + 1,
                        message: "Trailing whitespace",
                        ruleID: id
                    ))
                }
            }
        }

        return warnings
    }
}

private extension String {
    var trailingWhitespaceCount: Int {
        var count = 0
        for char in self.reversed() {
            if char.isWhitespace && char != "\n" {
                count += 1
            } else {
                break
            }
        }
        return count
    }
}
