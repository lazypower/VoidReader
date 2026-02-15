import SwiftUI
import VoidReaderCore

/// Renders markdown text as native SwiftUI content.
struct MarkdownReaderView: View {
    let text: String
    var blocks: [MarkdownBlock] = []
    var onTaskToggle: ((Int, Bool) -> Void)?
    var onMermaidExpand: ((String) -> Void)?

    var body: some View {
        // Use provided blocks or render if empty (fallback for previews)
        let renderBlocks = blocks.isEmpty ? BlockRenderer.render(text) : blocks

        VStack(alignment: .leading, spacing: 16) {
            ForEach(renderBlocks) { block in
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

        case .mermaid(let mermaidData):
            MermaidBlockView(data: mermaidData, onExpand: onMermaidExpand)
        }
    }
}

/// Preference key for tracking block positions.
struct BlockPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Renders markdown with block-level anchors for scroll navigation.
struct MarkdownReaderViewWithAnchors: View {
    let text: String
    let headings: [HeadingInfo]
    var blocks: [MarkdownBlock] = []
    var searchText: String = ""
    var caseSensitive: Bool = false
    var useRegex: Bool = false
    var currentMatchIndex: Int = 0
    var onTaskToggle: ((Int, Bool) -> Void)?
    var onTopBlockChange: ((Int) -> Void)?
    var onMermaidExpand: ((String) -> Void)?

    var body: some View {
        // Use provided blocks or render if empty (fallback)
        let renderBlocks = blocks.isEmpty ? BlockRenderer.render(text) : blocks
        let matchInfo = computeMatchInfo(blocks: renderBlocks)

        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(renderBlocks.enumerated()), id: \.offset) { index, block in
                // Add match anchor if this block contains the current match
                if let matchIdx = matchInfo.blockToFirstMatch[index], matchIdx == currentMatchIndex {
                    Color.clear.frame(height: 0).id("match-\(currentMatchIndex)")
                }

                BlockView(
                    block: block,
                    searchText: searchText,
                    matchRanges: matchInfo.blockMatches[index] ?? [],
                    onTaskToggle: onTaskToggle,
                    onMermaidExpand: onMermaidExpand
                )
                .id("block-\(index)")
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: BlockPositionPreferenceKey.self,
                            value: [index: geo.frame(in: .named("reader-scroll")).minY]
                        )
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onPreferenceChange(BlockPositionPreferenceKey.self) { positions in
            // Find the topmost block that's at or above the top of the viewport
            let topBlock = positions
                .filter { $0.value <= 60 } // Within ~60pt of top (accounting for padding)
                .max(by: { $0.value < $1.value }) // Highest Y value still above threshold

            if let blockIndex = topBlock?.key {
                onTopBlockChange?(blockIndex)
            }
        }
    }

    struct MatchInfo {
        var blockMatches: [Int: [Range<String.Index>]] = [:] // block index -> match ranges in that block's text
        var blockToFirstMatch: [Int: Int] = [:] // block index -> first match index in that block
    }

    private func computeMatchInfo(blocks: [MarkdownBlock]) -> MatchInfo {
        guard !searchText.isEmpty else { return MatchInfo() }

        var info = MatchInfo()
        var globalMatchIndex = 0

        for (blockIdx, block) in blocks.enumerated() {
            guard case .text(let attrString) = block else { continue }

            let blockText = String(attrString.characters)
            let matches = TextSearcher.findMatches(
                query: searchText,
                in: blockText,
                caseSensitive: caseSensitive,
                useRegex: useRegex
            )

            if !matches.isEmpty {
                info.blockMatches[blockIdx] = matches.map { $0.range }
                info.blockToFirstMatch[blockIdx] = globalMatchIndex
                globalMatchIndex += matches.count
            }
        }

        return info
    }

    /// Finds which block contains the given heading text.
    static func blockIndex(for headingText: String, in blocks: [MarkdownBlock]) -> Int? {
        for (idx, block) in blocks.enumerated() {
            if case .text(let attr) = block,
               String(attr.characters).contains(headingText) {
                return idx
            }
        }
        return nil
    }

    /// Finds which block contains the Nth match (0-indexed).
    static func blockIndexForMatch(
        _ matchIndex: Int,
        searchText: String,
        caseSensitive: Bool = false,
        useRegex: Bool = false,
        in blocks: [MarkdownBlock]
    ) -> Int? {
        guard !searchText.isEmpty else { return nil }

        var globalMatchIndex = 0

        for (blockIdx, block) in blocks.enumerated() {
            guard case .text(let attrString) = block else { continue }

            let blockText = String(attrString.characters)
            let matches = TextSearcher.findMatches(
                query: searchText,
                in: blockText,
                caseSensitive: caseSensitive,
                useRegex: useRegex
            )

            if globalMatchIndex + matches.count > matchIndex {
                return blockIdx
            }
            globalMatchIndex += matches.count
        }

        return nil
    }
}

/// Individual block view.
private struct BlockView: View {
    let block: MarkdownBlock
    var searchText: String = ""
    var matchRanges: [Range<String.Index>] = []
    var onTaskToggle: ((Int, Bool) -> Void)?
    var onMermaidExpand: ((String) -> Void)?

    var body: some View {
        switch block {
        case .text(let attributedString):
            if !searchText.isEmpty && !matchRanges.isEmpty {
                Text(highlightedString(attributedString))
                    .textSelection(.enabled)
            } else {
                Text(attributedString)
                    .textSelection(.enabled)
            }

        case .table(let tableData):
            TableBlockView(data: tableData)

        case .taskList(let items):
            TaskListView(items: items, onToggle: onTaskToggle)

        case .codeBlock(let codeData):
            CodeBlockView(data: codeData)

        case .image(let imageData):
            ImageBlockView(data: imageData)

        case .mermaid(let mermaidData):
            MermaidBlockView(data: mermaidData, onExpand: onMermaidExpand)
        }
    }

    private func highlightedString(_ original: AttributedString) -> AttributedString {
        var result = original
        let originalText = String(original.characters)

        // Apply highlight background to match ranges
        for range in matchRanges {
            // Convert String.Index range to AttributedString range
            let startOffset = originalText.distance(from: originalText.startIndex, to: range.lowerBound)
            let endOffset = originalText.distance(from: originalText.startIndex, to: range.upperBound)

            let attrStart = result.index(result.startIndex, offsetByCharacters: startOffset)
            let attrEnd = result.index(result.startIndex, offsetByCharacters: endOffset)

            result[attrStart..<attrEnd].backgroundColor = .yellow
            result[attrStart..<attrEnd].foregroundColor = .black
        }

        return result
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
