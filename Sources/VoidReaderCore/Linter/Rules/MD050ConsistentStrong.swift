import Foundation
import Markdown

/// MD050: Strong (bold) markers should be consistent — all `**` or all `__`.
/// Split from MD049 (which now covers only emphasis), matching markdownlint.
public struct MD050ConsistentStrong: LintRule {
    public let id = "MD050"
    public let description = "Strong markers should be consistent"

    public init() {}

    public func check(document: Document, source: String) -> [LintWarning] {
        var scanner = MarkerScanner(source: source, target: .strong)
        scanner.visit(document)
        return MarkerScanner.consistencyWarnings(scanner.markers, ruleID: id)
    }
}
