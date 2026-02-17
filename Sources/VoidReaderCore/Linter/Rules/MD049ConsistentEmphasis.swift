import Foundation
import Markdown

/// MD049: Emphasis markers should be consistent.
/// All emphasis should use the same marker style (* or _).
public struct MD049ConsistentEmphasis: LintRule {
    public let id = "MD049"
    public let description = "Emphasis markers should be consistent"

    public init() {}

    public func check(document: Document, source: String) -> [LintWarning] {
        var warnings: [LintWarning] = []

        // Find all emphasis markers in source
        var markers: [(line: Int, column: Int, marker: Character)] = []

        var walker = EmphasisWalker(source: source)
        walker.visit(document)
        markers = walker.markers

        guard !markers.isEmpty else { return [] }

        // Use the first marker as the expected style
        let expectedMarker = markers[0].marker

        for item in markers.dropFirst() {
            if item.marker != expectedMarker {
                warnings.append(LintWarning(
                    line: item.line,
                    column: item.column,
                    message: "Expected '\(expectedMarker)' but found '\(item.marker)'",
                    ruleID: id
                ))
            }
        }

        return warnings
    }
}

private struct EmphasisWalker: MarkupWalker {
    let source: String
    let lines: [String]
    var markers: [(line: Int, column: Int, marker: Character)] = []

    init(source: String) {
        self.source = source
        self.lines = source.components(separatedBy: "\n")
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> () {
        if let range = emphasis.range {
            let line = range.lowerBound.line
            let column = range.lowerBound.column

            // Get the marker from source
            if line <= lines.count {
                let lineText = lines[line - 1]
                let startIndex = lineText.index(lineText.startIndex, offsetBy: max(0, column - 1), limitedBy: lineText.endIndex) ?? lineText.startIndex

                if startIndex < lineText.endIndex {
                    let marker = lineText[startIndex]
                    if marker == "*" || marker == "_" {
                        markers.append((line: line, column: column, marker: marker))
                    }
                }
            }
        }

        descendInto(emphasis)
    }

    mutating func visitStrong(_ strong: Strong) -> () {
        if let range = strong.range {
            let line = range.lowerBound.line
            let column = range.lowerBound.column

            // Get the marker from source
            if line <= lines.count {
                let lineText = lines[line - 1]
                let startIndex = lineText.index(lineText.startIndex, offsetBy: max(0, column - 1), limitedBy: lineText.endIndex) ?? lineText.startIndex

                if startIndex < lineText.endIndex {
                    let marker = lineText[startIndex]
                    if marker == "*" || marker == "_" {
                        markers.append((line: line, column: column, marker: marker))
                    }
                }
            }
        }

        descendInto(strong)
    }
}
