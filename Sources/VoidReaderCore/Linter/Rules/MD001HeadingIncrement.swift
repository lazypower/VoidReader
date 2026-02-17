import Foundation
import Markdown

/// MD001: Heading levels should increment by one level at a time.
/// Example violation: # H1 followed by ### H3 (skipped H2)
public struct MD001HeadingIncrement: LintRule {
    public let id = "MD001"
    public let description = "Heading levels should increment by one"

    public init() {}

    public func check(document: Document, source: String) -> [LintWarning] {
        var warnings: [LintWarning] = []
        var lastLevel = 0

        for child in document.children {
            guard let heading = child as? Heading else { continue }

            let currentLevel = heading.level

            // Check if we skipped a level (e.g., H1 -> H3)
            if lastLevel > 0 && currentLevel > lastLevel + 1 {
                let line = heading.range?.lowerBound.line ?? 1
                warnings.append(LintWarning(
                    line: line,
                    column: 1,
                    message: "Heading level jumped from \(lastLevel) to \(currentLevel)",
                    ruleID: id
                ))
            }

            lastLevel = currentLevel
        }

        return warnings
    }
}
