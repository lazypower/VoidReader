import Foundation
import Markdown

/// MD022: Headings should be surrounded by blank lines.
public struct MD022BlankLinesAroundHeadings: LintRule {
    public let id = "MD022"
    public let description = "Headings should have blank lines around them"

    public init() {}

    public func check(document: Document, source: String) -> [LintWarning] {
        var warnings: [LintWarning] = []
        let lines = source.components(separatedBy: "\n")

        for child in document.children {
            guard let heading = child as? Heading,
                  let range = heading.range else { continue }

            let headingLine = range.lowerBound.line

            // Check line before heading (if not first line)
            if headingLine > 1 {
                let prevLine = lines[headingLine - 2] // -2 because 1-indexed and we want previous
                if !prevLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    warnings.append(LintWarning(
                        line: headingLine,
                        column: 1,
                        message: "Heading should have a blank line before it",
                        ruleID: id
                    ))
                }
            }

            // Check line after heading (if not last line)
            let headingEndLine = range.upperBound.line
            if headingEndLine < lines.count {
                let nextLine = lines[headingEndLine] // upperBound.line is 1-indexed
                if !nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    warnings.append(LintWarning(
                        line: headingLine,
                        column: 1,
                        message: "Heading should have a blank line after it",
                        ruleID: id
                    ))
                }
            }
        }

        return warnings
    }
}
