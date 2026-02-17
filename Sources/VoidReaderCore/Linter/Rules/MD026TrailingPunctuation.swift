import Foundation
import Markdown

/// MD026: Headings should not end with punctuation.
public struct MD026TrailingPunctuation: LintRule {
    public let id = "MD026"
    public let description = "No trailing punctuation in headings"

    /// Characters that are not allowed at the end of headings.
    private let punctuation: Set<Character> = [".", ",", ";", ":", "!"]

    public init() {}

    public func check(document: Document, source: String) -> [LintWarning] {
        var warnings: [LintWarning] = []

        for child in document.children {
            guard let heading = child as? Heading,
                  let range = heading.range else { continue }

            let text = heading.plainText.trimmingCharacters(in: .whitespaces)

            guard let lastChar = text.last else { continue }

            // Allow question marks (legitimate for heading questions)
            if punctuation.contains(lastChar) {
                warnings.append(LintWarning(
                    line: range.lowerBound.line,
                    column: range.lowerBound.column,
                    message: "Heading ends with punctuation '\(lastChar)'",
                    ruleID: id
                ))
            }
        }

        return warnings
    }
}
