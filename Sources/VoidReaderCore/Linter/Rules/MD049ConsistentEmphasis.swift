import Foundation
import Markdown

/// MD049: Emphasis (italic) markers should be consistent — all `*` or all `_`.
/// Strong (bold) consistency is a *separate* rule (MD050), matching markdownlint;
/// pooling them flagged a valid `_italic_` + `**bold**` document as inconsistent.
public struct MD049ConsistentEmphasis: LintRule {
    public let id = "MD049"
    public let description = "Emphasis markers should be consistent"

    public init() {}

    public func check(document: Document, source: String) -> [LintWarning] {
        var scanner = MarkerScanner(source: source, target: .emphasis)
        scanner.visit(document)
        return MarkerScanner.consistencyWarnings(scanner.markers, ruleID: id)
    }
}

/// Collects emphasis OR strong marker characters from source and flags any that
/// differ from the first. Shared by MD049 (emphasis) and MD050 (strong) so the
/// two consistency checks stay independent.
struct MarkerScanner: MarkupWalker {
    enum Target { case emphasis, strong }

    let lines: [String]
    let target: Target
    var markers: [(line: Int, column: Int, marker: Character)] = []

    init(source: String, target: Target) {
        self.lines = source.components(separatedBy: "\n")
        self.target = target
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        if target == .emphasis { collect(emphasis.range) }
        descendInto(emphasis)
    }

    mutating func visitStrong(_ strong: Strong) {
        if target == .strong { collect(strong.range) }
        descendInto(strong)
    }

    private mutating func collect(_ range: SourceRange?) {
        guard let range, range.lowerBound.line >= 1, range.lowerBound.line <= lines.count else { return }
        let line = range.lowerBound.line
        let column = range.lowerBound.column
        let lineText = lines[line - 1]
        let startIndex = lineText.index(
            lineText.startIndex, offsetBy: max(0, column - 1), limitedBy: lineText.endIndex
        ) ?? lineText.startIndex
        guard startIndex < lineText.endIndex else { return }
        let marker = lineText[startIndex]
        if marker == "*" || marker == "_" {
            markers.append((line: line, column: column, marker: marker))
        }
    }

    static func consistencyWarnings(
        _ markers: [(line: Int, column: Int, marker: Character)], ruleID: String
    ) -> [LintWarning] {
        guard let expected = markers.first?.marker else { return [] }
        return markers.dropFirst().compactMap { item in
            item.marker == expected ? nil : LintWarning(
                line: item.line,
                column: item.column,
                message: "Expected '\(expected)' but found '\(item.marker)'",
                ruleID: ruleID
            )
        }
    }
}
