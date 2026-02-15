import Foundation
import SwiftUI
import AppKit
import Markdown

/// Applies syntax highlighting to markdown source text using swift-markdown AST.
public struct MarkdownSyntaxHighlighter {

    /// Highlights markdown source and returns an NSAttributedString
    public static func highlight(
        _ source: String,
        theme: AppTheme,
        colorScheme: ColorScheme,
        font: NSFont
    ) -> NSAttributedString {
        let palette = theme.palette(for: colorScheme)

        // Create base attributed string with default styling
        let result = NSMutableAttributedString(string: source)
        let fullRange = NSRange(location: 0, length: result.length)

        // Base attributes
        result.addAttribute(.font, value: font, range: fullRange)
        result.addAttribute(.foregroundColor, value: NSColor(palette.text), range: fullRange)

        // Parse markdown
        let document = Document(parsing: source, options: [.parseBlockDirectives, .parseSymbolLinks])

        // Walk AST and apply syntax colors
        var walker = SyntaxColorWalker(source: source, result: result, palette: palette, font: font)
        walker.visit(document)

        return result
    }
}

/// Walks markdown AST and applies syntax highlighting colors
private struct SyntaxColorWalker: MarkupWalker {
    let source: String
    let result: NSMutableAttributedString
    let palette: ThemePalette
    let font: NSFont

    // MARK: - Headings (Mauve)

    mutating func visitHeading(_ heading: Heading) {
        applyColor(palette.mauve, to: heading)
        descendInto(heading)
    }

    // MARK: - Emphasis (Subtext for markers)

    mutating func visitStrong(_ strong: Strong) {
        applyColor(palette.subtext0, to: strong, markersOnly: true, markerLength: 2)
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        applyColor(palette.subtext0, to: emphasis, markersOnly: true, markerLength: 1)
        descendInto(emphasis)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        applyColor(palette.subtext0, to: strikethrough, markersOnly: true, markerLength: 2)
        descendInto(strikethrough)
    }

    // MARK: - Links (Blue)

    mutating func visitLink(_ link: Markdown.Link) {
        applyColor(palette.blue, to: link)
        descendInto(link)
    }

    // Autolinks are handled as regular links in swift-markdown

    // MARK: - Code (Green)

    mutating func visitInlineCode(_ code: InlineCode) {
        applyColor(palette.green, to: code)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        applyColor(palette.green, to: codeBlock)
    }

    // MARK: - List Markers (Teal)

    mutating func visitUnorderedList(_ list: UnorderedList) {
        // Color just the markers for each item
        for item in list.listItems {
            colorListMarker(item, color: palette.teal)
        }
        descendInto(list)
    }

    mutating func visitOrderedList(_ list: OrderedList) {
        for item in list.listItems {
            colorListMarker(item, color: palette.teal)
        }
        descendInto(list)
    }

    // MARK: - Blockquotes (Lavender)

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        // Color the > marker
        if let range = blockQuote.range {
            let offset = charOffset(from: range.lowerBound)
            if let offset = offset, offset < source.count {
                let markerRange = NSRange(location: offset, length: 1)
                result.addAttribute(.foregroundColor, value: NSColor(palette.lavender), range: markerRange)
            }
        }
        descendInto(blockQuote)
    }

    // MARK: - Thematic Break (Subtext)

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        applyColor(palette.subtext0, to: thematicBreak)
    }

    // MARK: - Images (Blue, like links)

    mutating func visitImage(_ image: Markdown.Image) {
        applyColor(palette.blue, to: image)
    }

    // MARK: - Tables (Subtext for structure)

    mutating func visitTable(_ table: Markdown.Table) {
        // Color the pipe characters
        if let range = table.range,
           let startOffset = charOffset(from: range.lowerBound),
           let endOffset = charOffset(from: range.upperBound) {
            let tableText = String(source.dropFirst(startOffset).prefix(endOffset - startOffset))
            var currentOffset = startOffset
            for char in tableText {
                if char == "|" || char == "-" {
                    let charRange = NSRange(location: currentOffset, length: 1)
                    if charRange.location + charRange.length <= result.length {
                        result.addAttribute(.foregroundColor, value: NSColor(palette.subtext0), range: charRange)
                    }
                }
                currentOffset += 1
            }
        }
        descendInto(table)
    }

    // MARK: - Helpers

    private mutating func descendInto(_ markup: Markup) {
        for child in markup.children {
            visit(child)
        }
    }

    private func applyColor(_ color: Color, to markup: Markup, markersOnly: Bool = false, markerLength: Int = 0) {
        guard let range = markup.range,
              let startOffset = charOffset(from: range.lowerBound),
              let endOffset = charOffset(from: range.upperBound) else {
            return
        }

        if markersOnly && markerLength > 0 {
            // Color only the opening and closing markers
            let openRange = NSRange(location: startOffset, length: markerLength)
            let closeRange = NSRange(location: endOffset - markerLength, length: markerLength)

            if openRange.location + openRange.length <= result.length {
                result.addAttribute(.foregroundColor, value: NSColor(color), range: openRange)
            }
            if closeRange.location + closeRange.length <= result.length && closeRange.location >= openRange.location + openRange.length {
                result.addAttribute(.foregroundColor, value: NSColor(color), range: closeRange)
            }
        } else {
            let nsRange = NSRange(location: startOffset, length: endOffset - startOffset)
            if nsRange.location + nsRange.length <= result.length {
                result.addAttribute(.foregroundColor, value: NSColor(color), range: nsRange)
            }
        }
    }

    private func colorListMarker(_ item: ListItem, color: Color) {
        guard let range = item.range,
              let startOffset = charOffset(from: range.lowerBound) else {
            return
        }

        // Find the marker (-, *, +, or number.)
        let lineStart = startOffset
        var markerEnd = lineStart

        // Scan for marker end (space after marker)
        let startIndex = source.index(source.startIndex, offsetBy: lineStart, limitedBy: source.endIndex) ?? source.endIndex
        var idx = startIndex
        while idx < source.endIndex && source[idx] != "\n" {
            if source[idx] == " " && idx > startIndex {
                markerEnd = source.distance(from: source.startIndex, to: idx)
                break
            }
            idx = source.index(after: idx)
        }

        if markerEnd > lineStart {
            let markerRange = NSRange(location: lineStart, length: markerEnd - lineStart)
            if markerRange.location + markerRange.length <= result.length {
                result.addAttribute(.foregroundColor, value: NSColor(color), range: markerRange)
            }
        }
    }

    /// Convert SourceLocation (line:column) to character offset
    private func charOffset(from loc: SourceLocation) -> Int? {
        var offset = 0
        var currentLine = 1

        for char in source {
            if currentLine == loc.line {
                return offset + (loc.column - 1)
            }
            if char == "\n" {
                currentLine += 1
            }
            offset += 1
        }

        // If we're on the last line
        if currentLine == loc.line {
            return offset + (loc.column - 1)
        }

        return nil
    }
}
