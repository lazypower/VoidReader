import AppKit
import SwiftUI
import VoidReaderCore

/// An NSView that renders markdown content for printing.
/// Uses NSTextView for AttributedString content and custom drawing for tables/code blocks.
final class PrintableMarkdownView: NSView {
    private let text: String
    private let pageSize: NSSize
    private let margins: NSEdgeInsets

    // Calculated layout
    private var renderedBlocks: [RenderedBlock] = []
    private var totalHeight: CGFloat = 0

    init(text: String, pageSize: NSSize = NSSize(width: 612, height: 792), margins: NSEdgeInsets = NSEdgeInsets(top: 72, left: 72, bottom: 72, right: 72)) {
        self.text = text
        self.pageSize = pageSize
        self.margins = margins
        super.init(frame: .zero)

        calculateLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout Calculation

    private var contentWidth: CGFloat {
        pageSize.width - margins.left - margins.right
    }

    private func calculateLayout() {
        let blocks = BlockRenderer.render(text)
        renderedBlocks = []
        var yOffset: CGFloat = margins.top

        for block in blocks {
            let rendered = layoutBlock(block, at: yOffset)
            renderedBlocks.append(rendered)
            yOffset += rendered.height + 12 // Block spacing
        }

        totalHeight = yOffset + margins.bottom

        // Set frame to fit all content
        self.frame = NSRect(x: 0, y: 0, width: pageSize.width, height: max(totalHeight, pageSize.height))
    }

    private func layoutBlock(_ block: MarkdownBlock, at yOffset: CGFloat) -> RenderedBlock {
        let xOffset = margins.left

        switch block {
        case .text(let attributedString):
            let nsAttrString = NSAttributedString(attributedString)
            let textStorage = NSTextStorage(attributedString: nsAttrString)
            let layoutManager = NSLayoutManager()
            let textContainer = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
            textContainer.lineFragmentPadding = 0

            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)

            return RenderedBlock(
                type: .text(nsAttrString),
                frame: NSRect(x: xOffset, y: yOffset, width: contentWidth, height: usedRect.height)
            )

        case .codeBlock(let data):
            let codeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            let codeAttrs: [NSAttributedString.Key: Any] = [
                .font: codeFont,
                .foregroundColor: NSColor.textColor
            ]
            let nsAttrString = NSAttributedString(string: data.code, attributes: codeAttrs)

            let textStorage = NSTextStorage(attributedString: nsAttrString)
            let layoutManager = NSLayoutManager()
            let textContainer = NSTextContainer(size: NSSize(width: contentWidth - 24, height: .greatestFiniteMagnitude))
            textContainer.lineFragmentPadding = 0

            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)

            return RenderedBlock(
                type: .codeBlock(nsAttrString),
                frame: NSRect(x: xOffset, y: yOffset, width: contentWidth, height: usedRect.height + 24)
            )

        case .table(let data):
            let height = calculateTableHeight(data)
            return RenderedBlock(
                type: .table(data),
                frame: NSRect(x: xOffset, y: yOffset, width: contentWidth, height: height)
            )

        case .taskList(let items):
            let itemHeight: CGFloat = 20
            let height = CGFloat(items.count) * itemHeight
            return RenderedBlock(
                type: .taskList(items),
                frame: NSRect(x: xOffset, y: yOffset, width: contentWidth, height: height)
            )

        case .image(let data):
            // For print, just show placeholder text for images
            return RenderedBlock(
                type: .imagePlaceholder(data.altText),
                frame: NSRect(x: xOffset, y: yOffset, width: contentWidth, height: 24)
            )

        case .mermaid:
            // For print, show placeholder for mermaid diagrams
            return RenderedBlock(
                type: .mermaidPlaceholder,
                frame: NSRect(x: xOffset, y: yOffset, width: contentWidth, height: 48)
            )

        case .mathBlock(let data):
            // For print, show placeholder with LaTeX source
            return RenderedBlock(
                type: .mathPlaceholder(data.latex),
                frame: NSRect(x: xOffset, y: yOffset, width: contentWidth, height: 32)
            )
        }
    }

    private func calculateTableHeight(_ data: TableData) -> CGFloat {
        let rowHeight: CGFloat = 28
        let headerHeight: CGFloat = 32
        return headerHeight + CGFloat(data.rows.count) * rowHeight
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Draw white background
        NSColor.white.setFill()
        dirtyRect.fill()

        for rendered in renderedBlocks {
            if dirtyRect.intersects(rendered.frame) {
                drawBlock(rendered)
            }
        }
    }

    private func drawBlock(_ rendered: RenderedBlock) {
        switch rendered.type {
        case .text(let attrString):
            attrString.draw(in: rendered.frame)

        case .codeBlock(let attrString):
            // Draw background
            let bgRect = rendered.frame.insetBy(dx: 0, dy: 0)
            NSColor(white: 0.95, alpha: 1.0).setFill()
            let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4)
            bgPath.fill()

            // Draw border
            NSColor(white: 0.85, alpha: 1.0).setStroke()
            bgPath.lineWidth = 0.5
            bgPath.stroke()

            // Draw code text
            let textRect = rendered.frame.insetBy(dx: 12, dy: 12)
            attrString.draw(in: textRect)

        case .table(let data):
            drawTable(data, in: rendered.frame)

        case .taskList(let items):
            drawTaskList(items, in: rendered.frame)

        case .imagePlaceholder(let altText):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let text = "[\(altText)]"
            (text as NSString).draw(in: rendered.frame, withAttributes: attrs)

        case .mermaidPlaceholder:
            // Draw placeholder box for mermaid diagram
            NSColor(white: 0.95, alpha: 1.0).setFill()
            let bgPath = NSBezierPath(roundedRect: rendered.frame.insetBy(dx: 0, dy: 4), xRadius: 4, yRadius: 4)
            bgPath.fill()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let text = "[Mermaid Diagram]"
            let textRect = rendered.frame.insetBy(dx: 12, dy: 12)
            (text as NSString).draw(in: textRect, withAttributes: attrs)

        case .mathPlaceholder(let latex):
            // Draw placeholder showing LaTeX source
            NSColor(white: 0.95, alpha: 1.0).setFill()
            let bgPath = NSBezierPath(roundedRect: rendered.frame.insetBy(dx: 0, dy: 4), xRadius: 4, yRadius: 4)
            bgPath.fill()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let displayText = "$$\(latex)$$"
            let textRect = rendered.frame.insetBy(dx: 12, dy: 8)
            (displayText as NSString).draw(in: textRect, withAttributes: attrs)
        }
    }

    private func drawTable(_ data: TableData, in rect: NSRect) {
        let columnCount = data.headers.count
        guard columnCount > 0 else { return }

        let columnWidth = rect.width / CGFloat(columnCount)
        let rowHeight: CGFloat = 28
        let headerHeight: CGFloat = 32

        let headerFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let bodyFont = NSFont.systemFont(ofSize: 12, weight: .regular)

        // Draw header background
        let headerRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: headerHeight)
        NSColor(white: 0.93, alpha: 1.0).setFill()
        headerRect.fill()

        // Draw header cells
        for (i, cell) in data.headers.enumerated() {
            let cellRect = NSRect(
                x: rect.minX + CGFloat(i) * columnWidth + 8,
                y: rect.minY + 8,
                width: columnWidth - 16,
                height: headerHeight - 16
            )
            let attrs: [NSAttributedString.Key: Any] = [
                .font: headerFont,
                .foregroundColor: NSColor.textColor
            ]
            let text = String(cell.content.characters)
            (text as NSString).draw(in: cellRect, withAttributes: attrs)
        }

        // Draw body rows
        for (rowIndex, row) in data.rows.enumerated() {
            let rowY = rect.minY + headerHeight + CGFloat(rowIndex) * rowHeight

            // Alternate row background
            if rowIndex % 2 == 1 {
                let rowRect = NSRect(x: rect.minX, y: rowY, width: rect.width, height: rowHeight)
                NSColor(white: 0.97, alpha: 1.0).setFill()
                rowRect.fill()
            }

            for (colIndex, cell) in row.enumerated() {
                let cellRect = NSRect(
                    x: rect.minX + CGFloat(colIndex) * columnWidth + 8,
                    y: rowY + 6,
                    width: columnWidth - 16,
                    height: rowHeight - 12
                )
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: bodyFont,
                    .foregroundColor: NSColor.textColor
                ]
                let text = String(cell.content.characters)
                (text as NSString).draw(in: cellRect, withAttributes: attrs)
            }
        }

        // Draw table border
        NSColor(white: 0.85, alpha: 1.0).setStroke()
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 0.5
        borderPath.stroke()
    }

    private func drawTaskList(_ items: [TaskItem], in rect: NSRect) {
        let itemHeight: CGFloat = 20
        let checkboxSize: CGFloat = 12
        let font = NSFont.systemFont(ofSize: 12)

        for (i, item) in items.enumerated() {
            let itemY = rect.minY + CGFloat(i) * itemHeight

            // Draw checkbox
            let checkboxRect = NSRect(
                x: rect.minX,
                y: itemY + (itemHeight - checkboxSize) / 2,
                width: checkboxSize,
                height: checkboxSize
            )

            NSColor(white: 0.7, alpha: 1.0).setStroke()
            let checkboxPath = NSBezierPath(roundedRect: checkboxRect, xRadius: 2, yRadius: 2)
            checkboxPath.lineWidth = 1
            checkboxPath.stroke()

            if item.isChecked {
                // Draw checkmark
                NSColor.textColor.setStroke()
                let checkPath = NSBezierPath()
                checkPath.move(to: NSPoint(x: checkboxRect.minX + 2, y: checkboxRect.midY))
                checkPath.line(to: NSPoint(x: checkboxRect.midX - 1, y: checkboxRect.minY + 2))
                checkPath.line(to: NSPoint(x: checkboxRect.maxX - 2, y: checkboxRect.maxY - 2))
                checkPath.lineWidth = 1.5
                checkPath.stroke()
            }

            // Draw text
            let textRect = NSRect(
                x: rect.minX + checkboxSize + 8,
                y: itemY + 2,
                width: rect.width - checkboxSize - 8,
                height: itemHeight - 4
            )
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: item.isChecked ? NSColor.secondaryLabelColor : NSColor.textColor,
                .strikethroughStyle: item.isChecked ? NSUnderlineStyle.single.rawValue : 0
            ]
            let text = String(item.content.characters)
            (text as NSString).draw(in: textRect, withAttributes: attrs)
        }
    }

    // MARK: - Printing

    override var isFlipped: Bool { true }

    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        let pageCount = Int(ceil(totalHeight / pageSize.height))
        range.pointee = NSRange(location: 1, length: max(pageCount, 1))
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect {
        let pageIndex = page - 1
        let pageY = CGFloat(pageIndex) * pageSize.height
        return NSRect(x: 0, y: pageY, width: pageSize.width, height: pageSize.height)
    }
}

// MARK: - Supporting Types

private struct RenderedBlock {
    enum BlockType {
        case text(NSAttributedString)
        case codeBlock(NSAttributedString)
        case table(TableData)
        case taskList([TaskItem])
        case imagePlaceholder(String)
        case mermaidPlaceholder
        case mathPlaceholder(String)
    }

    let type: BlockType
    let frame: NSRect

    var height: CGFloat { frame.height }
}

// MARK: - Print Helper

enum DocumentPrinter {
    /// Prints the given markdown text.
    static func print(text: String, from window: NSWindow?) {
        let printView = PrintableMarkdownView(text: text)

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72

        let printOperation = NSPrintOperation(view: printView, printInfo: printInfo)
        printOperation.showsPrintPanel = true
        printOperation.showsProgressPanel = true

        if let window = window {
            printOperation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            printOperation.run()
        }
    }

    /// Exports the markdown text to PDF, prompting for save location.
    static func exportPDF(text: String, suggestedName: String, from window: NSWindow?) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = suggestedName.replacingOccurrences(of: ".md", with: ".pdf")
        savePanel.title = "Export as PDF"

        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = savePanel.url else { return }

            let printView = PrintableMarkdownView(text: text)

            // Configure print info for PDF output
            let printInfo = NSPrintInfo()
            printInfo.paperSize = NSSize(width: 612, height: 792) // US Letter
            printInfo.topMargin = 72
            printInfo.bottomMargin = 72
            printInfo.leftMargin = 72
            printInfo.rightMargin = 72
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
            printInfo.isHorizontallyCentered = true
            printInfo.isVerticallyCentered = false

            // Set to save to file
            printInfo.jobDisposition = .save
            printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

            let printOperation = NSPrintOperation(view: printView, printInfo: printInfo)
            printOperation.showsPrintPanel = false
            printOperation.showsProgressPanel = true

            printOperation.run()
        }

        if let window = window {
            savePanel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(savePanel.runModal())
        }
    }
}
