import Foundation
import Markdown
import SwiftUI

/// Renders markdown to an array of content blocks, supporting tables and task lists.
public struct BlockRenderer {

    /// Renders markdown text to an array of content blocks.
    public static func render(_ text: String, style: MarkdownRenderer.Style = .init()) -> [MarkdownBlock] {
        let document = MarkdownParser.parse(text)
        var walker = BlockWalker(style: style)
        walker.visit(document)
        walker.flushTextBuffer()
        return walker.blocks
    }
}

/// Walks the markdown AST and produces content blocks.
struct BlockWalker: MarkupWalker {
    let style: MarkdownRenderer.Style
    var blocks: [MarkdownBlock] = []

    // Text accumulator for inline content
    private var textBuffer = AttributedString()
    private var isFirstBlock = true

    // State tracking for inline formatting
    private var isBold = false
    private var isItalic = false
    private var isStrikethrough = false
    private var headingLevel: Int? = nil
    private var listDepth: Int = 0
    private var orderedListCounters: [Int] = []

    init(style: MarkdownRenderer.Style) {
        self.style = style
    }

    // MARK: - Buffer Management

    mutating func flushTextBuffer() {
        if !textBuffer.characters.isEmpty {
            blocks.append(.text(textBuffer))
            textBuffer = AttributedString()
        }
    }

    private mutating func addBlockSpacing() {
        if !isFirstBlock && !textBuffer.characters.isEmpty {
            textBuffer += AttributedString("\n\n")
        }
        isFirstBlock = false
    }

    private func currentFont() -> Font {
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

        if isBold { weight = .bold }

        var font = style.makeFont(size: size, weight: weight)
        if isItalic { font = font.italic() }
        return font
    }

    // MARK: - Block Elements

    mutating func visitDocument(_ document: Document) {
        for child in document.children {
            visit(child)
        }
    }

    mutating func visitHeading(_ heading: Heading) {
        addBlockSpacing()
        headingLevel = heading.level
        for child in heading.children {
            visit(child)
        }
        headingLevel = nil
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        // Check if paragraph contains only a single image (make it a block)
        let children = Array(paragraph.children)
        if children.count == 1, let image = children.first as? Markdown.Image {
            flushTextBuffer()
            isFirstBlock = false
            blocks.append(.image(ImageData(
                source: image.source ?? "",
                altText: image.plainText,
                title: image.title
            )))
            return
        }

        addBlockSpacing()
        for child in paragraph.children {
            visit(child)
        }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        flushTextBuffer()
        isFirstBlock = false

        let code = codeBlock.code.hasSuffix("\n")
            ? String(codeBlock.code.dropLast())
            : codeBlock.code

        // Detect mermaid diagrams
        if codeBlock.language?.lowercased() == "mermaid" {
            blocks.append(.mermaid(MermaidData(source: code)))
        } else {
            blocks.append(.codeBlock(CodeBlockData(
                code: code,
                language: codeBlock.language
            )))
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        addBlockSpacing()

        var marker = AttributedString("│ ")
        marker.font = style.makeFont(size: style.bodySize).italic()
        marker.foregroundColor = .secondary
        textBuffer += marker

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

    mutating func visitTable(_ table: Markdown.Table) {
        flushTextBuffer()
        isFirstBlock = false

        var headers: [TableCell] = []
        var rows: [[TableCell]] = []
        var alignments: [TableAlignment] = []

        // Extract alignments from table
        for colAlign in table.columnAlignments {
            let alignment: TableAlignment
            switch colAlign {
            case .left: alignment = .left
            case .right: alignment = .right
            case .center: alignment = .center
            case .none: alignment = .left
            }
            alignments.append(alignment)
        }

        // Extract header cells
        for child in table.head.children {
            if let cell = child as? Markdown.Table.Cell {
                let content = renderInlineContent(cell)
                headers.append(TableCell(content: content))
            }
        }

        // Ensure alignments match header count
        while alignments.count < headers.count {
            alignments.append(.left)
        }

        // Extract body rows
        for child in table.body.children {
            if let row = child as? Markdown.Table.Row {
                var rowCells: [TableCell] = []
                for cellChild in row.children {
                    if let cell = cellChild as? Markdown.Table.Cell {
                        let content = renderInlineContent(cell)
                        rowCells.append(TableCell(content: content))
                    }
                }
                rows.append(rowCells)
            }
        }

        blocks.append(.table(TableData(headers: headers, rows: rows, alignments: alignments)))
    }

    mutating func visitUnorderedList(_ list: UnorderedList) {
        // Check if this is a task list
        let isTaskList = list.listItems.contains { item in
            item.checkbox != nil
        }

        if isTaskList {
            flushTextBuffer()
            isFirstBlock = false

            var tasks: [TaskItem] = []
            for item in list.listItems {
                let isChecked = item.checkbox == .checked
                let content = renderListItemContent(item)
                tasks.append(TaskItem(isChecked: isChecked, content: content))
            }
            blocks.append(.taskList(tasks))
        } else {
            // Regular unordered list
            if listDepth == 0 {
                addBlockSpacing()
            }

            listDepth += 1
            for item in list.listItems {
                visitListItem(item)
            }
            listDepth -= 1
        }
    }

    mutating func visitOrderedList(_ list: OrderedList) {
        if listDepth == 0 {
            addBlockSpacing()
        }

        listDepth += 1
        orderedListCounters.append(Int(list.startIndex))

        for item in list.listItems {
            visitListItem(item)
            orderedListCounters[orderedListCounters.count - 1] += 1
        }

        orderedListCounters.removeLast()
        listDepth -= 1
    }

    mutating func visitListItem(_ item: ListItem) {
        if !(listDepth == 1 && textBuffer.characters.isEmpty) {
            textBuffer += AttributedString("\n")
        }

        let indent = String(repeating: "    ", count: listDepth - 1)
        let marker: String
        if orderedListCounters.isEmpty {
            marker = "•"
        } else {
            marker = "\(orderedListCounters.last ?? 1)."
        }

        var markerString = AttributedString("\(indent)\(marker) ")
        markerString.font = currentFont()
        markerString.foregroundColor = .secondary
        textBuffer += markerString

        for child in item.children {
            if let paragraph = child as? Paragraph {
                for pChild in paragraph.children {
                    visit(pChild)
                }
            } else {
                visit(child)
            }
        }
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        addBlockSpacing()
        var hrString = AttributedString("───────────────────────────────")
        hrString.foregroundColor = .secondary
        textBuffer += hrString
    }

    // MARK: - Inline Elements

    mutating func visitText(_ text: Markdown.Text) {
        var textString = AttributedString(text.string)
        textString.font = currentFont()
        textString.foregroundColor = .primary
        if isStrikethrough {
            textString.strikethroughStyle = .single
        }
        textBuffer += textString
    }

    mutating func visitStrong(_ strong: Strong) {
        let saved = isBold
        isBold = true
        for child in strong.children { visit(child) }
        isBold = saved
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        let saved = isItalic
        isItalic = true
        for child in emphasis.children { visit(child) }
        isItalic = saved
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        let saved = isStrikethrough
        isStrikethrough = true
        for child in strikethrough.children { visit(child) }
        isStrikethrough = saved
    }

    mutating func visitInlineCode(_ code: InlineCode) {
        var attrs = AttributeContainer()
        attrs.font = style.makeCodeFont(size: style.codeSize)
        attrs.foregroundColor = .primary
        attrs.backgroundColor = Color(nsColor: .quaternaryLabelColor).opacity(0.5)

        var codeString = AttributedString(code.code)
        codeString.mergeAttributes(attrs)
        textBuffer += codeString
    }

    mutating func visitLink(_ link: Markdown.Link) {
        var attrs = AttributeContainer()
        attrs.font = currentFont()
        attrs.foregroundColor = Color.accentColor
        if let destination = link.destination, let url = URL(string: destination) {
            attrs.link = url
        }

        for child in link.children {
            if let text = child as? Markdown.Text {
                var linkString = AttributedString(text.string)
                linkString.mergeAttributes(attrs)
                textBuffer += linkString
            } else {
                visit(child)
            }
        }
    }


    mutating func visitImage(_ image: Markdown.Image) {
        var attrs = AttributeContainer()
        attrs.foregroundColor = .secondary
        let altText = image.plainText.isEmpty ? "[Image]" : "🖼 \(image.plainText)"
        var imageString = AttributedString(altText)
        imageString.mergeAttributes(attrs)
        textBuffer += imageString
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        textBuffer += AttributedString(" ")
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        textBuffer += AttributedString("\n")
    }

    // MARK: - Helpers

    /// Renders inline content (for table cells, etc.)
    private func renderInlineContent(_ markup: Markup) -> AttributedString {
        var result = AttributedString()
        for child in markup.children {
            if let text = child as? Markdown.Text {
                var str = AttributedString(text.string)
                str.font = style.makeFont(size: style.bodySize)
                result += str
            } else if let strong = child as? Strong {
                var str = renderInlineContent(strong)
                str.font = style.makeFont(size: style.bodySize, weight: .bold)
                result += str
            } else if let emphasis = child as? Emphasis {
                var str = renderInlineContent(emphasis)
                str.font = style.makeFont(size: style.bodySize).italic()
                result += str
            } else if let code = child as? InlineCode {
                var str = AttributedString(code.code)
                str.font = style.makeCodeFont(size: style.codeSize)
                str.backgroundColor = Color(nsColor: .quaternaryLabelColor).opacity(0.5)
                result += str
            } else if let link = child as? Markdown.Link {
                var str = renderInlineContent(link)
                str.foregroundColor = Color.accentColor
                if let dest = link.destination, let url = URL(string: dest) {
                    str.link = url
                }
                result += str
            }
        }
        return result
    }

    /// Renders list item content (without the checkbox)
    private func renderListItemContent(_ item: ListItem) -> AttributedString {
        var result = AttributedString()
        for child in item.children {
            if let para = child as? Paragraph {
                result += renderInlineContent(para)
            }
        }
        return result
    }
}
