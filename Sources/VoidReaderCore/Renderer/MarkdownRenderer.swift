import Foundation
import Markdown
import SwiftUI

/// Renders markdown text to AttributedString for native display.
public struct MarkdownRenderer {

    /// Styling configuration for rendered markdown.
    public struct Style {
        // Base typography
        public var bodySize: CGFloat = 16
        public var bodyWeight: Font.Weight = .regular
        public var fontFamily: String? = nil  // nil = system font

        // Heading scale (relative to body size)
        public var h1Scale: CGFloat = 2.0
        public var h2Scale: CGFloat = 1.5
        public var h3Scale: CGFloat = 1.25
        public var h4Scale: CGFloat = 1.1
        public var h5Scale: CGFloat = 1.0
        public var h6Scale: CGFloat = 0.9

        // Code styling
        public var codeSize: CGFloat = 14
        public var codeFontFamily: String? = nil  // nil = system mono

        // Paragraph spacing
        public var paragraphSpacing: CGFloat = 12
        public var headingSpacing: CGFloat = 20

        // Theme colors (nil = use system semantic colors)
        public var textColor: Color? = nil          // nil → .primary
        public var secondaryColor: Color? = nil     // nil → .secondary
        public var linkColor: Color? = nil          // nil → Color.accentColor
        public var codeBackground: Color? = nil     // nil → quaternaryLabelColor
        public var mathColor: Color? = nil          // nil → purple accent for math
        public var headingColor: Color? = nil       // nil → textColor
        public var listMarkerColor: Color? = nil    // nil → secondaryColor
        public var blockquoteColor: Color? = nil    // nil → secondaryColor

        public init() {}

        /// Resolved text color (semantic or themed)
        public var resolvedTextColor: Color {
            textColor ?? .primary
        }

        /// Resolved secondary color (semantic or themed)
        public var resolvedSecondaryColor: Color {
            secondaryColor ?? .secondary
        }

        /// Resolved link color (semantic or themed)
        public var resolvedLinkColor: Color {
            linkColor ?? Color.accentColor
        }

        /// Resolved code background (semantic or themed)
        public var resolvedCodeBackground: Color {
            codeBackground ?? Color(nsColor: .quaternaryLabelColor).opacity(0.5)
        }

        /// Resolved math color (semantic or themed)
        public var resolvedMathColor: Color {
            mathColor ?? Color.purple
        }

        /// Resolved heading color (falls back to text color)
        public var resolvedHeadingColor: Color {
            headingColor ?? resolvedTextColor
        }

        /// Resolved list marker color (falls back to secondary color)
        public var resolvedListMarkerColor: Color {
            listMarkerColor ?? resolvedSecondaryColor
        }

        /// Resolved blockquote color (falls back to secondary color)
        public var resolvedBlockquoteColor: Color {
            blockquoteColor ?? resolvedSecondaryColor
        }

        /// Creates a font with the configured family
        public func makeFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            if let family = fontFamily {
                return .custom(family, size: size)
            }
            return .system(size: size, weight: weight)
        }

        /// Creates a code font with the configured family
        public func makeCodeFont(size: CGFloat) -> Font {
            if let family = codeFontFamily {
                return .custom(family, size: size)
            }
            return .system(size: size, design: .monospaced)
        }
    }

    /// Renders markdown text to an AttributedString.
    /// - Parameters:
    ///   - text: The markdown source text
    ///   - style: Styling configuration
    /// - Returns: Rendered AttributedString suitable for display in SwiftUI Text views
    public static func render(_ text: String, style: Style = Style()) throws -> AttributedString {
        let document = MarkdownParser.parse(text)
        var walker = AttributedStringWalker(style: style)
        walker.visit(document)
        return walker.result
    }
}

// MARK: - AttributedString Walker

/// Walks the markdown AST and builds an AttributedString.
struct AttributedStringWalker: MarkupWalker {
    let style: MarkdownRenderer.Style
    var result = AttributedString()

    // State tracking
    private var isBold = false
    private var isItalic = false
    private var isCode = false
    private var headingLevel: Int? = nil
    private var listDepth: Int = 0
    private var orderedListCounters: [Int] = []
    private var isFirstBlock = true

    init(style: MarkdownRenderer.Style) {
        self.style = style
    }

    private func currentFont() -> Font {
        if isCode {
            return .system(size: style.codeSize, design: .monospaced)
        }

        var size = style.bodySize
        var weight: Font.Weight = style.bodyWeight

        if let level = headingLevel {
            let scale: CGFloat
            switch level {
            case 1: scale = style.h1Scale
            case 2: scale = style.h2Scale
            case 3: scale = style.h3Scale
            case 4: scale = style.h4Scale
            case 5: scale = style.h5Scale
            default: scale = style.h6Scale
            }
            size = style.bodySize * scale
            weight = .bold
        }

        if isBold {
            weight = .bold
        }

        var font = Font.system(size: size, weight: weight)
        if isItalic {
            font = font.italic()
        }
        return font
    }

    // MARK: - Block Elements

    mutating func visitDocument(_ document: Document) -> () {
        for child in document.children {
            visit(child)
        }
    }

    mutating func visitHeading(_ heading: Heading) -> () {
        addBlockSpacing()

        headingLevel = heading.level

        for child in heading.children {
            visit(child)
        }

        headingLevel = nil
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> () {
        addBlockSpacing()

        for child in paragraph.children {
            visit(child)
        }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> () {
        addBlockSpacing()

        var attrs = AttributeContainer()
        attrs.font = .system(size: style.codeSize, design: .monospaced)
        attrs.foregroundColor = style.resolvedTextColor
        attrs.backgroundColor = style.resolvedCodeBackground

        // Trim trailing newline from code blocks
        let code = codeBlock.code.hasSuffix("\n")
            ? String(codeBlock.code.dropLast())
            : codeBlock.code

        var codeString = AttributedString(code)
        codeString.mergeAttributes(attrs)
        result += codeString
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> () {
        addBlockSpacing()

        var attrs = AttributeContainer()
        attrs.font = .system(size: style.bodySize).italic()
        attrs.foregroundColor = style.resolvedSecondaryColor

        // Add quote marker
        var marker = AttributedString("│ ")
        marker.mergeAttributes(attrs)
        result += marker

        let savedItalic = isItalic
        isItalic = true

        for child in blockQuote.children {
            if let para = child as? Paragraph {
                for pChild in para.children {
                    visit(pChild)
                }
            } else {
                visit(child)
            }
        }

        isItalic = savedItalic
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> () {
        if listDepth == 0 {
            addBlockSpacing()
        }

        listDepth += 1
        for item in list.listItems {
            visit(item)
        }
        listDepth -= 1
    }

    mutating func visitOrderedList(_ list: OrderedList) -> () {
        if listDepth == 0 {
            addBlockSpacing()
        }

        listDepth += 1
        orderedListCounters.append(Int(list.startIndex))

        for item in list.listItems {
            visit(item)
            orderedListCounters[orderedListCounters.count - 1] += 1
        }

        orderedListCounters.removeLast()
        listDepth -= 1
    }

    mutating func visitListItem(_ item: ListItem) -> () {
        // Newline before each list item (except first at depth 1)
        if !(listDepth == 1 && result.characters.isEmpty) {
            result += AttributedString("\n")
        }

        // Indentation
        let indent = String(repeating: "    ", count: listDepth - 1)

        // Bullet or number
        let marker: String
        if orderedListCounters.isEmpty {
            marker = "•"
        } else {
            marker = "\(orderedListCounters.last ?? 1)."
        }

        var markerString = AttributedString("\(indent)\(marker) ")
        markerString.font = currentFont()
        markerString.foregroundColor = style.resolvedSecondaryColor
        result += markerString

        for child in item.children {
            // Skip nested paragraph wrapper
            if let paragraph = child as? Paragraph {
                for pChild in paragraph.children {
                    visit(pChild)
                }
            } else {
                visit(child)
            }
        }
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> () {
        addBlockSpacing()

        var hrString = AttributedString("───────────────────────────────")
        hrString.foregroundColor = style.resolvedSecondaryColor
        result += hrString
    }

    // MARK: - Inline Elements

    mutating func visitText(_ text: Markdown.Text) -> () {
        let source = text.string

        // Check for inline math
        let mathMatches = InlineMathParser.extract(from: source)

        if mathMatches.isEmpty {
            // No math - render as plain text
            var textString = AttributedString(source)
            textString.font = currentFont()
            textString.foregroundColor = style.resolvedTextColor
            result += textString
        } else {
            // Has inline math - render segments
            var currentIndex = source.startIndex

            for match in mathMatches {
                // Render text before this match
                if currentIndex < match.range.lowerBound {
                    let beforeText = String(source[currentIndex..<match.range.lowerBound])
                    var beforeString = AttributedString(beforeText)
                    beforeString.font = currentFont()
                    beforeString.foregroundColor = style.resolvedTextColor
                    result += beforeString
                }

                // Render the math expression (styled)
                var mathString = AttributedString(match.latex)
                mathString.font = .system(size: style.codeSize, design: .monospaced)
                mathString.foregroundColor = style.resolvedMathColor
                mathString.backgroundColor = style.resolvedCodeBackground
                result += mathString

                currentIndex = match.range.upperBound
            }

            // Render remaining text after last match
            if currentIndex < source.endIndex {
                let afterText = String(source[currentIndex...])
                var afterString = AttributedString(afterText)
                afterString.font = currentFont()
                afterString.foregroundColor = style.resolvedTextColor
                result += afterString
            }
        }
    }

    mutating func visitStrong(_ strong: Strong) -> () {
        let saved = isBold
        isBold = true

        for child in strong.children {
            visit(child)
        }

        isBold = saved
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> () {
        let saved = isItalic
        isItalic = true

        for child in emphasis.children {
            visit(child)
        }

        isItalic = saved
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> () {
        for child in strikethrough.children {
            visit(child)
        }
        // Note: AttributedString strikethrough needs to be applied after
        // For now, we'll handle this with a post-process or different approach
    }

    mutating func visitInlineCode(_ code: InlineCode) -> () {
        var attrs = AttributeContainer()
        attrs.font = .system(size: style.codeSize, design: .monospaced)
        attrs.foregroundColor = style.resolvedTextColor
        attrs.backgroundColor = style.resolvedCodeBackground

        var codeString = AttributedString(code.code)
        codeString.mergeAttributes(attrs)
        result += codeString
    }

    mutating func visitLink(_ link: Markdown.Link) -> () {
        var attrs = AttributeContainer()
        attrs.font = currentFont()
        attrs.foregroundColor = style.resolvedLinkColor
        if let destination = link.destination, let url = URL(string: destination) {
            attrs.link = url
        }

        for child in link.children {
            if let text = child as? Markdown.Text {
                var linkString = AttributedString(text.string)
                linkString.mergeAttributes(attrs)
                result += linkString
            } else {
                visit(child)
            }
        }
    }

    mutating func visitImage(_ image: Markdown.Image) -> () {
        // For now, show alt text as placeholder
        // TODO: Async image loading in Section 8
        var attrs = AttributeContainer()
        attrs.foregroundColor = style.resolvedSecondaryColor

        let altText = image.plainText.isEmpty ? "[Image]" : "🖼 \(image.plainText)"
        var imageString = AttributedString(altText)
        imageString.mergeAttributes(attrs)
        result += imageString
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> () {
        result += AttributedString(" ")
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> () {
        result += AttributedString("\n")
    }

    // MARK: - Helpers

    private mutating func addBlockSpacing() {
        if !isFirstBlock {
            result += AttributedString("\n\n")
        }
        isFirstBlock = false
    }
}
