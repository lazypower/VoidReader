import Foundation
import Markdown

/// MD004: Unordered list markers should be consistent.
/// All lists should use the same marker style (-, *, or +).
public struct MD004ConsistentListMarkers: LintRule {
    public let id = "MD004"
    public let description = "Unordered list markers should be consistent"

    public init() {}

    public func check(document: Document, source: String) -> [LintWarning] {
        var warnings: [LintWarning] = []
        let sourceLines = SourceLines(source)

        // Find all unordered list items and their markers
        var markers: [(line: Int, marker: Character)] = []

        var walker = ListMarkerWalker(sourceLines: sourceLines, source: source)
        walker.visit(document)
        markers = walker.markers

        guard !markers.isEmpty else { return [] }

        // Use the first marker as the expected style
        let expectedMarker = markers[0].marker

        for item in markers.dropFirst() {
            if item.marker != expectedMarker {
                warnings.append(LintWarning(
                    line: item.line,
                    column: 1,
                    message: "Expected '\(expectedMarker)' but found '\(item.marker)'",
                    ruleID: id
                ))
            }
        }

        return warnings
    }
}

private struct ListMarkerWalker: MarkupWalker {
    let sourceLines: SourceLines
    let source: String
    var markers: [(line: Int, marker: Character)] = []

    mutating func visitListItem(_ listItem: ListItem) -> () {
        // Only check unordered list items
        guard let parent = listItem.parent, parent is UnorderedList else {
            descendInto(listItem)
            return
        }

        if let range = listItem.range {
            let line = range.lowerBound.line
            let lineText = sourceLines[line - 1]
            // Find the marker character (first non-whitespace)
            if let marker = lineText.first(where: { $0 == "-" || $0 == "*" || $0 == "+" }) {
                markers.append((line: line, marker: marker))
            }
        }

        descendInto(listItem)
    }
}
