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
        // Blank-line runs inside a fenced code block are intentional content, so
        // a fenced line ends the current run without counting toward it.
        let fence = FenceMap(lines: lines)

        var consecutiveBlankCount = 0
        var blankRunStart = 0

        func flushRun() {
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

        for (index, line) in lines.enumerated() {
            if fence.isProtected(index) {
                flushRun()
                continue
            }

            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                if consecutiveBlankCount == 0 {
                    blankRunStart = index + 1
                }
                consecutiveBlankCount += 1
            } else {
                flushRun()
            }
        }

        // Check at end of file
        flushRun()

        return warnings
    }
}
