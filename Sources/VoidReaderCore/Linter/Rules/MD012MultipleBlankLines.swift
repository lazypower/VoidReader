import Foundation
import Markdown

/// MD012: Multiple consecutive blank lines are not allowed.
public struct MD012MultipleBlankLines: LintRule {
    public let id = "MD012"
    public let description = "No multiple consecutive blank lines"

    public init() {}

    public func check(document: Document, source: String) -> [LintWarning] {
        var warnings: [LintWarning] = []
        let lines = source.components(separatedBy: "\n")

        var consecutiveBlankCount = 0
        var blankRunStart = 0

        for (index, line) in lines.enumerated() {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty

            if isBlank {
                if consecutiveBlankCount == 0 {
                    blankRunStart = index + 1
                }
                consecutiveBlankCount += 1
            } else {
                if consecutiveBlankCount > 1 {
                    warnings.append(LintWarning(
                        line: blankRunStart,
                        column: 1,
                        message: "Multiple consecutive blank lines (\(consecutiveBlankCount))",
                        ruleID: id
                    ))
                }
                consecutiveBlankCount = 0
            }
        }

        // Check at end of file
        if consecutiveBlankCount > 1 {
            warnings.append(LintWarning(
                line: blankRunStart,
                column: 1,
                message: "Multiple consecutive blank lines (\(consecutiveBlankCount))",
                ruleID: id
            ))
        }

        return warnings
    }
}
