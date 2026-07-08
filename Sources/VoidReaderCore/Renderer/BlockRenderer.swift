import Foundation
import Markdown
import SwiftUI

/// Renders markdown to an array of content blocks, supporting tables and task lists.
public struct BlockRenderer {

    /// Line count above which a fenced code block is split into multiple
    /// `CodeSegment`-bearing `.codeBlock` entries. At typical code font
    /// metrics (~16pt line height), 800 lines ≈ 12,800pt — well under the
    /// SwiftUI `ScrollView` hit-test ceiling (~50k pt) that pathological
    /// single blocks were crossing. Below the threshold, the block renders
    /// as a single row exactly as before.
    public static let segmentationLineThreshold = 800

    /// Split a code block's raw source into `segmentationLineThreshold`-line
    /// slices, joined by a shared `groupID`. Returns a single-element array
    /// for blocks under the threshold (no segment metadata attached).
    static func segmentCodeBlock(code: String, language: String?) -> [CodeBlockData] {
        // Split on newlines into Substrings. `split(omittingEmptySubsequences:
        // false)` matches `components(separatedBy:)` semantics (trailing \n
        // yields a final empty element) without allocating a [String] copy of
        // every line — material for the pathological-fence case this feature
        // targets. Substring is a copy-on-write view into `code`.
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > segmentationLineThreshold else {
            return [CodeBlockData(code: code, language: language)]
        }

        let groupID = UUID()
        let fullCode = code
        var segments: [CodeBlockData] = []
        var start = 0
        let perSegment = segmentationLineThreshold

        while start < lines.count {
            let end = min(start + perSegment, lines.count)
            let slice = lines[start..<end].joined(separator: "\n")
            segments.append(CodeBlockData(
                code: slice,
                language: language,
                segment: nil  // placeholder; filled in below once total is known
            ))
            start = end
        }

        let total = segments.count
        for i in 0..<total {
            segments[i] = CodeBlockData(
                code: segments[i].code,
                language: language,
                segment: CodeSegment(
                    groupID: groupID,
                    indexInGroup: i,
                    totalInGroup: total,
                    fullCode: fullCode
                )
            )
        }
        return segments
    }

    /// Renders markdown text to an array of content blocks.
    /// - Parameter isDocumentStart: True when `text` begins at byte 0 of the
    ///   document. Frontmatter is only recognized then — never for a progressive
    ///   chunk that happens to start with a `---` thematic break, which would
    ///   otherwise be misread as a frontmatter fence and have content swallowed.
    public static func render(
        _ text: String,
        style: MarkdownRenderer.Style = .init(),
        isDocumentStart: Bool = true
    ) -> [MarkdownBlock] {
        let charCount = text.count
        let byteCount = text.utf8.count

        // Signpost: parseMarkdown — bytes attached at begin, produced-node count at end (only
        // known after the walk completes). Uses raw signposter so OSLogMessage interpolation
        // stays lazy when not recording.
        let signposter = Signposts.signposter(for: .rendering)
        let signpostID = signposter.makeSignpostID()
        let signpostState = signposter.beginInterval(
            "parseMarkdown",
            id: signpostID,
            "bytes=\(byteCount)"
        )

        let allBlocks: [MarkdownBlock] = DebugLog.measure(.rendering, "BlockRenderer.render(\(charCount) chars)") {
            // Extract frontmatter before any other processing — but only when
            // this text is the true start of the document.
            let fmResult = isDocumentStart
                ? FrontmatterParser.parse(text)
                : FrontmatterParser.Result(frontmatter: nil, body: text)
            let bodyText = fmResult.body

            // Pre-process to extract math blocks ($$...$$)
            let segments = DebugLog.measure(.rendering, "  extractMathBlocks") {
                extractMathBlocks(from: bodyText)
            }

            var blocks: [MarkdownBlock] = []

            // Prepend frontmatter block if present
            if let fm = fmResult.frontmatter {
                blocks.append(.frontmatter(fm))
            }

            for segment in segments {
                switch segment {
                case .markdown(let mdText):
                    // Parse and render markdown segment
                    let document = DebugLog.measure(.rendering, "  MarkdownParser.parse(\(mdText.count) chars)") {
                        MarkdownParser.parse(mdText)
                    }

                    DebugLog.measure(.rendering, "  BlockWalker.visit") {
                        var walker = BlockWalker(style: style)
                        walker.visit(document)
                        walker.flushTextBuffer()
                        blocks.append(contentsOf: walker.blocks)
                    }

                case .math(let latex):
                    // Add math block directly
                    blocks.append(.mathBlock(MathData(latex: latex, isBlock: true)))
                }
            }

            DebugLog.log(.rendering, "  → produced \(blocks.count) blocks")
            return blocks
        }

        signposter.endInterval("parseMarkdown", signpostState, "nodes=\(allBlocks.count)")
        return allBlocks
    }

    /// Segments of content: either markdown text or math blocks
    private enum ContentSegment {
        case markdown(String)
        case math(String)
    }

    /// Extract $$...$$ math blocks from text, returning alternating segments.
    ///
    /// Fence-aware: a `$$` that falls on a fenced code line (shell `$$` PID,
    /// `Makefile` `$$var`, a TeX example in a ```tex block) is left alone, so the
    /// fence is never torn across two parses. Single pass over all matches — the
    /// previous version reallocated the whole remainder string per match (O(n²)).
    private static func extractMathBlocks(from text: String) -> [ContentSegment] {
        // Fast path: if no $$ markers, skip regex entirely
        guard text.contains("$$") else {
            return [.markdown(text)]
        }

        let lines = text.components(separatedBy: "\n")
        let fence = FenceMap(lines: lines)
        let lineStarts = lineStartIndices(text)
        func isFenced(_ idx: String.Index) -> Bool {
            fence.isProtected(lineNumber(of: idx, in: lineStarts))
        }

        // Collect every `$$` delimiter, tagging those that fall on fenced lines.
        // Pairing then ignores fenced delimiters entirely — crucially they are
        // *skipped*, not consumed, so a real `$$…$$` following a fenced `$$`
        // still pairs correctly instead of being swallowed by a cross-fence match.
        var openers: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while let delimiter = text.range(of: "$$", range: searchStart..<text.endIndex) {
            if !isFenced(delimiter.lowerBound) {
                openers.append(delimiter)
            }
            searchStart = delimiter.upperBound
        }

        // True if a fenced line sits strictly between two positions — a math
        // pair may not straddle a code fence (that would tear the fence and turn
        // its contents into "math"). The endpoints are unfenced by construction.
        func crossesFence(_ a: String.Index, _ b: String.Index) -> Bool {
            let lo = lineNumber(of: a, in: lineStarts)
            let hi = lineNumber(of: b, in: lineStarts)
            guard hi > lo else { return false }
            return ((lo + 1)..<hi).contains { fence.isProtected($0) }
        }

        var segments: [ContentSegment] = []
        var cursor = text.startIndex
        var i = 0
        while i + 1 < openers.count {
            let open = openers[i]
            let close = openers[i + 1]

            // If this opener can't reach the next delimiter without crossing a
            // fence, it's a stray `$$` — leave it as literal markdown and try the
            // next delimiter as a fresh opener (advance by one, not two).
            if crossesFence(open.upperBound, close.lowerBound) {
                i += 1
                continue
            }

            let latex = String(text[open.upperBound..<close.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if latex.isEmpty {
                // Empty `$$…$$` is not math — keep the delimiters as literal text
                // instead of dropping them (no content loss).
                if cursor < close.upperBound {
                    segments.append(.markdown(String(text[cursor..<close.upperBound])))
                }
            } else {
                if cursor < open.lowerBound {
                    segments.append(.markdown(String(text[cursor..<open.lowerBound])))
                }
                segments.append(.math(latex))
            }
            cursor = close.upperBound
            i += 2
        }

        if cursor < text.endIndex {
            segments.append(.markdown(String(text[cursor...])))
        }

        return segments.isEmpty ? [.markdown(text)] : segments
    }

    /// Byte-0 index of each line (line 0 starts at `startIndex`, each subsequent
    /// line just after a `\n`). Line numbering matches `components(separatedBy:)`
    /// and therefore ``FenceMap``.
    private static func lineStartIndices(_ text: String) -> [String.Index] {
        var starts = [text.startIndex]
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "\n" { starts.append(text.index(after: i)) }
            i = text.index(after: i)
        }
        return starts
    }

    /// 0-based line number containing `idx`, via binary search over line starts.
    private static func lineNumber(of idx: String.Index, in starts: [String.Index]) -> Int {
        var lo = 0, hi = starts.count - 1, answer = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if starts[mid] <= idx {
                answer = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return answer
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
    private var inBlockquote = false
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
        // Flush so the heading gets its own block — enables scroll-to-heading
        flushTextBuffer()
        isFirstBlock = false
        headingLevel = heading.level
        for child in heading.children {
            visit(child)
        }
        headingLevel = nil
        flushTextBuffer()
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
            // Split over-tall code blocks into segments. For blocks under
            // the threshold this returns a single-element array with
            // `segment == nil`, preserving the pre-change shape.
            let segments = BlockRenderer.segmentCodeBlock(code: code, language: codeBlock.language)
            for segment in segments {
                blocks.append(.codeBlock(segment))
            }
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        addBlockSpacing()

        var marker = AttributedString("│ ")
        marker.font = style.makeFont(size: style.bodySize).italic()
        marker.foregroundColor = style.resolvedBlockquoteColor
        textBuffer += marker

        let savedItalic = isItalic
        let savedInBlockquote = inBlockquote
        isItalic = true
        inBlockquote = true

        func quoteMarker() -> AttributedString {
            var m = AttributedString("│ ")
            m.font = style.makeFont(size: style.bodySize).italic()
            m.foregroundColor = style.resolvedBlockquoteColor
            return m
        }

        var emittedContent = false
        for child in blockQuote.children {
            if let para = child as? Paragraph {
                // Separate a paragraph from any preceding blockquote content with
                // a blank line and a fresh marker — otherwise paragraphs (or a
                // paragraph after a list) fuse with no boundary or lose the marker.
                if emittedContent {
                    textBuffer += AttributedString("\n\n")
                    textBuffer += quoteMarker()
                }
                for pChild in para.children {
                    visit(pChild)
                }
            } else {
                visit(child)
            }
            emittedContent = true
        }

        isItalic = savedItalic
        inBlockquote = savedInBlockquote
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
        markerString.foregroundColor = style.resolvedListMarkerColor
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
        hrString.foregroundColor = style.resolvedSecondaryColor
        textBuffer += hrString
    }

    // MARK: - Inline Elements

    mutating func visitText(_ text: Markdown.Text) {
        let source = text.string

        // Determine text color based on context
        let textColor: Color = if headingLevel != nil {
            style.resolvedHeadingColor
        } else if inBlockquote {
            style.resolvedBlockquoteColor
        } else {
            style.resolvedTextColor
        }

        // Check for inline math
        let mathMatches = InlineMathParser.extract(from: source)

        if mathMatches.isEmpty {
            // No math - render as plain text
            var textString = AttributedString(source)
            textString.font = currentFont()
            textString.foregroundColor = textColor
            if isStrikethrough {
                textString.strikethroughStyle = .single
            }
            textBuffer += textString
        } else {
            // Has inline math - render segments
            var currentIndex = source.startIndex

            for match in mathMatches {
                // Render text before this match
                if currentIndex < match.range.lowerBound {
                    let beforeText = String(source[currentIndex..<match.range.lowerBound])
                    var beforeString = AttributedString(beforeText)
                    beforeString.font = currentFont()
                    beforeString.foregroundColor = textColor
                    if isStrikethrough {
                        beforeString.strikethroughStyle = .single
                    }
                    textBuffer += beforeString
                }

                // Render the math expression (styled)
                var mathString = AttributedString(match.latex)
                mathString.font = .system(size: style.codeSize, design: .monospaced)
                mathString.foregroundColor = style.resolvedMathColor
                mathString.backgroundColor = style.resolvedCodeBackground
                textBuffer += mathString

                currentIndex = match.range.upperBound
            }

            // Render remaining text after last match
            if currentIndex < source.endIndex {
                let afterText = String(source[currentIndex...])
                var afterString = AttributedString(afterText)
                afterString.font = currentFont()
                afterString.foregroundColor = textColor
                if isStrikethrough {
                    afterString.strikethroughStyle = .single
                }
                textBuffer += afterString
            }
        }
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
        attrs.foregroundColor = style.resolvedTextColor
        attrs.backgroundColor = style.resolvedCodeBackground

        var codeString = AttributedString(code.code)
        codeString.mergeAttributes(attrs)
        textBuffer += codeString
    }

    mutating func visitLink(_ link: Markdown.Link) {
        var attrs = AttributeContainer()
        attrs.font = currentFont()
        attrs.foregroundColor = style.resolvedLinkColor
        if let destination = link.destination {
            if destination.hasPrefix("#") {
                // In-document anchor link → custom scheme for interception
                let fragment = String(destination.dropFirst())
                let slug = HeadingInfo.slug(from: fragment)
                if let url = URL(string: "void-anchor:\(slug)") {
                    attrs.link = url
                }
            } else if destination.contains("://") || destination.hasPrefix("mailto:") {
                // Absolute URL — pass through as-is
                if let url = URL(string: destination) {
                    attrs.link = url
                }
            } else {
                // Relative path — wrap in custom scheme so OpenURLAction can intercept
                let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? destination
                if let url = URL(string: "void-file:\(encoded)") {
                    attrs.link = url
                }
            }
        }

        // Remember where this link's content starts so styled children (e.g.
        // the bold in `[**bold**](url)`, which go through `visit`) can be given
        // the link + link color afterward — otherwise that run isn't clickable.
        let linkStart = textBuffer.endIndex
        for child in link.children {
            if let text = child as? Markdown.Text {
                var linkString = AttributedString(text.string)
                linkString.mergeAttributes(attrs)
                textBuffer += linkString
            } else {
                visit(child)
            }
        }
        if let url = attrs.link, linkStart < textBuffer.endIndex {
            let range = linkStart..<textBuffer.endIndex
            textBuffer[range].link = url
            textBuffer[range].foregroundColor = style.resolvedLinkColor
        }
    }


    mutating func visitImage(_ image: Markdown.Image) {
        var attrs = AttributeContainer()
        attrs.foregroundColor = style.resolvedSecondaryColor
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

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        let raw = inlineHTML.rawHTML
        let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed == "<br>" || trimmed == "<br/>" || trimmed == "<br />" {
            // A hard break — the one HTML tag with an obvious semantic mapping.
            textBuffer += AttributedString("\n")
        } else if trimmed.hasPrefix("<!--") {
            // Comment — intentionally invisible; drop it.
        } else {
            // Anything else: render the raw tag verbatim in monospace rather than
            // dropping it silently (README <kbd>, <sup>, <details>, etc.).
            var str = AttributedString(raw)
            str.font = style.makeCodeFont(size: style.codeSize)
            textBuffer += str
        }
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        let raw = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop pure comments; render other raw HTML blocks verbatim as a code
        // block so their content survives instead of vanishing.
        guard !raw.isEmpty, !(raw.hasPrefix("<!--") && raw.hasSuffix("-->")) else { return }
        flushTextBuffer()
        isFirstBlock = false
        // Segment like a fenced block so a huge HTML block doesn't become one
        // pathologically tall row.
        for segment in BlockRenderer.segmentCodeBlock(code: raw, language: "html") {
            blocks.append(.codeBlock(segment))
        }
    }

    // MARK: - Helpers

    /// Renders inline content (for table cells, etc.)
    private func renderInlineContent(_ markup: Markup) -> AttributedString {
        var result = AttributedString()
        for child in markup.children {
            if let text = child as? Markdown.Text {
                // Check for inline math in text
                let source = text.string
                let mathMatches = InlineMathParser.extract(from: source)

                if mathMatches.isEmpty {
                    var str = AttributedString(source)
                    str.font = style.makeFont(size: style.bodySize)
                    result += str
                } else {
                    var currentIndex = source.startIndex
                    for match in mathMatches {
                        if currentIndex < match.range.lowerBound {
                            let beforeText = String(source[currentIndex..<match.range.lowerBound])
                            var beforeString = AttributedString(beforeText)
                            beforeString.font = style.makeFont(size: style.bodySize)
                            result += beforeString
                        }
                        var mathString = AttributedString(match.latex)
                        mathString.font = .system(size: style.codeSize, design: .monospaced)
                        mathString.foregroundColor = style.resolvedMathColor
                        mathString.backgroundColor = style.resolvedCodeBackground
                        result += mathString
                        currentIndex = match.range.upperBound
                    }
                    if currentIndex < source.endIndex {
                        let afterText = String(source[currentIndex...])
                        var afterString = AttributedString(afterText)
                        afterString.font = style.makeFont(size: style.bodySize)
                        result += afterString
                    }
                }
            } else if let strong = child as? Strong {
                var str = renderInlineContent(strong)
                str.font = style.makeFont(size: style.bodySize, weight: .bold)
                result += str
            } else if let emphasis = child as? Emphasis {
                var str = renderInlineContent(emphasis)
                str.font = style.makeFont(size: style.bodySize).italic()
                result += str
            } else if let inlineHTML = child as? InlineHTML {
                // Preserve raw inline HTML here too (table cells, task items),
                // consistent with visitInlineHTML on the main path.
                let raw = inlineHTML.rawHTML
                let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
                if trimmed == "<br>" || trimmed == "<br/>" || trimmed == "<br />" {
                    result += AttributedString("\n")
                } else if !trimmed.hasPrefix("<!--") {
                    var str = AttributedString(raw)
                    str.font = style.makeCodeFont(size: style.codeSize)
                    result += str
                }
            } else if let code = child as? InlineCode {
                var str = AttributedString(code.code)
                str.font = style.makeCodeFont(size: style.codeSize)
                str.backgroundColor = style.resolvedCodeBackground
                result += str
            } else if let link = child as? Markdown.Link {
                var str = renderInlineContent(link)
                str.foregroundColor = style.resolvedLinkColor
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
