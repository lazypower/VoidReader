import AppKit
import Foundation
import VoidReaderCore

/// Prepares stable large-document row geometry away from the main actor.
/// Each call owns its TextKit objects, so no layout graph crosses threads.
enum DocumentBlockMeasurement {
    static func heights(
        for blocks: [MarkdownBlock],
        width: CGFloat,
        codeFont: NSFont
    ) -> [Int: CGFloat] {
        let contentWidth = max(1, width)
        let codeLineHeight = ceil(codeFont.ascender - codeFont.descender + codeFont.leading)
        var result: [Int: CGFloat] = [:]
        result.reserveCapacity(blocks.count)

        for (index, block) in blocks.enumerated() {
            let height: CGFloat
            switch block {
            case .text(let attributed):
                height = textHeight(attributed, width: contentWidth)

            case .codeBlock(let data):
                var lineCount = 1
                for character in data.code where character == "\n" { lineCount += 1 }
                height = CGFloat(lineCount) * codeLineHeight
                    + CodeBlockView.chromeHeight(
                        isFirst: data.isSegmentFirst,
                        isLast: data.isSegmentLast
                    )

            case .table(let data):
                let headerFont = TableMeasurement.headerFont(size: 14)
                let bodyFont = TableMeasurement.bodyFont(size: 14)
                let headerHeight = ceil(headerFont.ascender - headerFont.descender + headerFont.leading)
                    + TableMeasurement.headerVerticalPadding * 2
                let rowHeight = ceil(bodyFont.ascender - bodyFont.descender + bodyFont.leading)
                    + TableMeasurement.bodyVerticalPadding * 2
                height = headerHeight
                    + rowHeight * CGFloat(data.rows.count)
                    + CGFloat(max(0, data.rows.count))

            case .taskList(let items):
                let textWidth = max(1, contentWidth - 24)
                let minimumLineHeight = ceil(
                    NSFont.systemFont(ofSize: NSFont.systemFontSize).ascender
                    - NSFont.systemFont(ofSize: NSFont.systemFontSize).descender
                )
                let contentHeight = items.reduce(CGFloat.zero) { partial, item in
                    partial + max(minimumLineHeight, textHeight(item.content, width: textWidth))
                }
                height = contentHeight + CGFloat(max(0, items.count - 1)) * 4

            case .image, .mermaid, .mathBlock, .frontmatter:
                // These blocks resolve external/dynamic layout after display.
                // Their conservative slots avoid clipping; rare corrections
                // are handled separately from the ordinary scroll path.
                height = block.estimatedHeight
            }
            result[index] = max(1, ceil(height))
        }
        return result
    }

    private static func textHeight(_ attributed: AttributedString, width: CGFloat) -> CGFloat {
        autoreleasepool {
            let storage = NSTextStorage(attributedString: NSAttributedString(attributed))
            let layoutManager = NSLayoutManager()
            let container = NSTextContainer(
                size: NSSize(width: width, height: .greatestFiniteMagnitude)
            )
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            storage.addLayoutManager(layoutManager)
            layoutManager.ensureLayout(for: container)
            return ceil(layoutManager.usedRect(for: container).height)
        }
    }
}
