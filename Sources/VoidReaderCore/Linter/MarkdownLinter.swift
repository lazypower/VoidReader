import Foundation
import Markdown

/// Lints markdown documents using a collection of rules.
public struct MarkdownLinter {

    /// All available lint rules.
    public static let allRules: [LintRule] = [
        MD001HeadingIncrement(),
        MD004ConsistentListMarkers(),
        MD009TrailingWhitespace(),
        MD012MultipleBlankLines(),
        MD022BlankLinesAroundHeadings(),
        MD026TrailingPunctuation(),
        MD031BlankLinesAroundCodeBlocks(),
        MD049ConsistentEmphasis(),
    ]

    /// Lints markdown text and returns warnings.
    /// - Parameters:
    ///   - text: The markdown source text
    ///   - enabledRules: Set of rule IDs to run (nil = all rules)
    /// - Returns: Sorted array of warnings
    public static func lint(_ text: String, enabledRules: Set<String>? = nil) -> [LintWarning] {
        let document = Document(parsing: text)
        var warnings: [LintWarning] = []

        for rule in allRules {
            // Skip disabled rules
            if let enabled = enabledRules, !enabled.contains(rule.id) {
                continue
            }

            let ruleWarnings = rule.check(document: document, source: text)
            warnings.append(contentsOf: ruleWarnings)
        }

        return warnings.sorted()
    }

    /// Gets the set of all rule IDs.
    public static var allRuleIDs: Set<String> {
        Set(allRules.map { $0.id })
    }

    /// Gets a rule by ID.
    public static func rule(for id: String) -> LintRule? {
        allRules.first { $0.id == id }
    }
}
