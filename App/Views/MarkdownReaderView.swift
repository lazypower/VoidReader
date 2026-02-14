import SwiftUI
import VoidReaderCore

/// Renders markdown text as native SwiftUI content.
struct MarkdownReaderView: View {
    let text: String
    var onTaskToggle: ((Int, Bool) -> Void)?

    var body: some View {
        let blocks = BlockRenderer.render(text)

        VStack(alignment: .leading, spacing: 16) {
            ForEach(blocks) { block in
                blockView(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(for block: MarkdownBlock) -> some View {
        switch block {
        case .text(let attributedString):
            Text(attributedString)
                .textSelection(.enabled)

        case .table(let tableData):
            TableBlockView(data: tableData)

        case .taskList(let items):
            TaskListView(items: items, onToggle: onTaskToggle)

        case .codeBlock(let codeData):
            CodeBlockView(data: codeData)

        case .image(let imageData):
            ImageBlockView(data: imageData)
        }
    }
}

/// Renders markdown with block-level anchors for scroll navigation.
struct MarkdownReaderViewWithAnchors: View {
    let text: String
    let headings: [HeadingInfo]
    var onTaskToggle: ((Int, Bool) -> Void)?

    var body: some View {
        let blocks = BlockRenderer.render(text)

        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                BlockView(block: block, onTaskToggle: onTaskToggle)
                    .id("block-\(index)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Finds which block contains the given heading text.
    static func blockIndex(for headingText: String, in text: String) -> Int? {
        let blocks = BlockRenderer.render(text)
        for (idx, block) in blocks.enumerated() {
            if case .text(let attr) = block,
               String(attr.characters).contains(headingText) {
                return idx
            }
        }
        return nil
    }
}

/// Individual block view.
private struct BlockView: View {
    let block: MarkdownBlock
    var onTaskToggle: ((Int, Bool) -> Void)?

    var body: some View {
        switch block {
        case .text(let attributedString):
            Text(attributedString)
                .textSelection(.enabled)

        case .table(let tableData):
            TableBlockView(data: tableData)

        case .taskList(let items):
            TaskListView(items: items, onToggle: onTaskToggle)

        case .codeBlock(let codeData):
            CodeBlockView(data: codeData)

        case .image(let imageData):
            ImageBlockView(data: imageData)
        }
    }
}

#Preview("Full Document") {
    ScrollView {
        MarkdownReaderView(text: """
        # VoidReader Demo

        This is a **markdown** document with various elements.

        ## Features

        - Native rendering
        - Fast performance
        - GFM support

        ### Code Example

        ```swift
        let app = VoidReader()
        app.render(markdown)
        ```

        ### Task List

        - [x] Basic markdown
        - [x] Code blocks
        - [ ] Tables
        - [ ] Images

        ### Table Example

        | Feature | Status | Priority |
        |---------|:------:|-------:|
        | Tables | Done | High |
        | Tasks | Done | High |
        | Images | Pending | Medium |

        > This is a blockquote with some *emphasized* text.

        ---

        That's all for now!
        """)
        .padding(40)
        .frame(maxWidth: 720, alignment: .leading)
    }
    .frame(width: 800, height: 600)
}
