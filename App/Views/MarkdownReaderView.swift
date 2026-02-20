import SwiftUI
import VoidReaderCore

/// Renders markdown text as native SwiftUI content.
/// Uses LazyVStack for virtual scrolling performance on large documents.
struct MarkdownReaderView: View {
    let text: String
    var blocks: [MarkdownBlock] = []
    var documentURL: URL? = nil
    var codeFontSize: CGFloat = 13
    var codeFontFamily: String? = nil
    var onTaskToggle: ((Int, Bool) -> Void)?
    var onMermaidExpand: ((String) -> Void)?

    var body: some View {
        // Use provided blocks or render if empty (fallback for previews)
        let renderBlocks = blocks.isEmpty ? BlockRenderer.render(text) : blocks

        LazyVStack(alignment: .leading, spacing: 16) {
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
            CodeBlockView(data: codeData, fontSize: codeFontSize, fontFamily: codeFontFamily)

        case .image(let imageData):
            ImageBlockView(data: imageData, documentURL: documentURL)

        case .mermaid(let mermaidData):
            MermaidBlockView(data: mermaidData, onExpand: onMermaidExpand)

        case .mathBlock(let mathData):
            MathBlockView(latex: mathData.latex)
        }
    }
}

/// Debounced scroll position tracker - only fires after scrolling stops
struct ScrollPositionTracker: View {
    let coordinateSpace: String
    let blockCount: Int
    let onPositionUpdate: (Int, Int) -> Void

    @State private var debounceTask: Task<Void, Never>?
    @State private var currentOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    currentOffset = -geo.frame(in: .named(coordinateSpace)).minY
                    reportPosition()
                }
                .onChange(of: geo.frame(in: .named(coordinateSpace)).minY) { _, newY in
                    currentOffset = -newY
                    scheduleUpdate()
                }
        }
        .frame(height: 0)
    }

    private func scheduleUpdate() {
        // Cancel any pending update
        debounceTask?.cancel()

        // Schedule new update after scroll stops (200ms idle)
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            reportPosition()
        }
    }

    private func reportPosition() {
        let estimatedBlockHeight: CGFloat = 60
        let estimatedIndex = max(0, min(blockCount - 1, Int(currentOffset / estimatedBlockHeight)))
        let percent = blockCount > 1 ? (estimatedIndex * 100) / (blockCount - 1) : 0
        onPositionUpdate(estimatedIndex, min(100, max(0, percent)))
    }
}

/// Renders markdown with block-level anchors for scroll navigation.
/// Uses LazyVStack for virtual scrolling performance on large documents.
struct MarkdownReaderViewWithAnchors: View {
    let text: String
    let headings: [HeadingInfo]
    var blocks: [MarkdownBlock] = []
    var documentURL: URL? = nil
    var searchText: String = ""
    var caseSensitive: Bool = false
    var useRegex: Bool = false
    var currentMatchIndex: Int = 0
    var codeFontSize: CGFloat = 13
    var codeFontFamily: String? = nil
    var onTaskToggle: ((Int, Bool) -> Void)?
    var onTopBlockChange: ((Int) -> Void)?
    var onScrollProgress: ((Int) -> Void)?  // Reports percent read (0-100)
    var onMermaidExpand: ((String) -> Void)?

    /// Cached search match info - only recomputed when search changes
    @State private var cachedMatchInfo: MatchInfo = MatchInfo()
    @State private var lastSearchKey: String = ""

    /// Cached block count to avoid recalculating
    @State private var blockCount: Int = 0

    /// Last reported scroll position to avoid redundant updates
    @State private var lastReportedBlockIndex: Int = -1
    @State private var lastReportedOffset: CGFloat = 0

    /// Chunk size for large document virtualization
    private static let chunkSize = 100

    var body: some View {
        // Use provided blocks - empty means still loading (don't fallback to sync render)
        let renderBlocks = blocks

        // For large documents, use chunked rendering to reduce LazyVStack item count
        if renderBlocks.count > 1000 {
            chunkedContent(blocks: renderBlocks)
                .onAppear {
                    DebugLog.log(.rendering, "Chunked content appearing: \(renderBlocks.count) blocks")
                }
        } else {
            directContent(blocks: renderBlocks)
        }
    }

    /// Direct rendering for smaller documents (< 1000 blocks)
    @ViewBuilder
    private func directContent(blocks renderBlocks: [MarkdownBlock]) -> some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(renderBlocks.indices, id: \.self) { index in
                blockContent(at: index, in: renderBlocks)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scrollTracker)
        .onAppear { setupState(blocks: renderBlocks) }
        .onChange(of: renderBlocks.count) { _, newCount in blockCount = newCount }
        .onChange(of: searchText) { _, _ in updateMatchInfoIfNeeded(blocks: renderBlocks) }
        .onChange(of: caseSensitive) { _, _ in updateMatchInfoIfNeeded(blocks: renderBlocks) }
        .onChange(of: useRegex) { _, _ in updateMatchInfoIfNeeded(blocks: renderBlocks) }
    }

    /// Chunked rendering for large documents - reduces LazyVStack items from N to N/100
    @ViewBuilder
    private func chunkedContent(blocks renderBlocks: [MarkdownBlock]) -> some View {
        let chunkCount = (renderBlocks.count + Self.chunkSize - 1) / Self.chunkSize

        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(0..<chunkCount, id: \.self) { chunkIndex in
                let startIdx = chunkIndex * Self.chunkSize
                let endIdx = min(startIdx + Self.chunkSize, renderBlocks.count)

                // Each chunk is a VStack of its blocks with estimated total height
                ChunkView(
                    blocks: renderBlocks,
                    startIndex: startIdx,
                    endIndex: endIdx,
                    documentURL: documentURL,
                    searchText: searchText,
                    cachedMatchInfo: cachedMatchInfo,
                    currentMatchIndex: currentMatchIndex,
                    codeFontSize: codeFontSize,
                    codeFontFamily: codeFontFamily,
                    onTaskToggle: onTaskToggle,
                    onMermaidExpand: onMermaidExpand
                )
                .id("chunk-\(chunkIndex)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scrollTracker)
        .onAppear { setupState(blocks: renderBlocks) }
        .onChange(of: renderBlocks.count) { _, newCount in blockCount = newCount }
        .onChange(of: searchText) { _, _ in updateMatchInfoIfNeeded(blocks: renderBlocks) }
        .onChange(of: caseSensitive) { _, _ in updateMatchInfoIfNeeded(blocks: renderBlocks) }
        .onChange(of: useRegex) { _, _ in updateMatchInfoIfNeeded(blocks: renderBlocks) }
    }

    /// Individual block content with anchors
    @ViewBuilder
    private func blockContent(at index: Int, in renderBlocks: [MarkdownBlock]) -> some View {
        // Add match anchor if this block contains the current match
        if let matchIdx = cachedMatchInfo.blockToFirstMatch[index], matchIdx == currentMatchIndex {
            Color.clear.frame(height: 0).id("match-\(currentMatchIndex)")
        }

        BlockView(
            block: renderBlocks[index],
            documentURL: documentURL,
            searchText: searchText,
            matchRanges: cachedMatchInfo.blockMatches[index] ?? [],
            codeFontSize: codeFontSize,
            codeFontFamily: codeFontFamily,
            onTaskToggle: onTaskToggle,
            onMermaidExpand: onMermaidExpand
        )
        .frame(minHeight: renderBlocks[index].estimatedHeight)
        .id("block-\(index)")
    }

    private func setupState(blocks: [MarkdownBlock]) {
        blockCount = blocks.count
        updateMatchInfoIfNeeded(blocks: blocks)
    }

    /// Scroll tracker - only updates after scroll stops (debounced)
    /// Disabled for very large documents (>3000 blocks) - causes scroll jank
    @ViewBuilder
    private var scrollTracker: some View {
        if blockCount > 0 && blockCount < 3000 {
            ScrollPositionTracker(
                coordinateSpace: "reader-scroll",
                blockCount: blockCount,
                onPositionUpdate: handleScrollUpdate
            )
        }
    }

    /// Handle debounced scroll position update
    private func handleScrollUpdate(blockIndex: Int, percent: Int) {
        guard blockIndex != lastReportedBlockIndex else { return }
        lastReportedBlockIndex = blockIndex
        onTopBlockChange?(blockIndex)
        onScrollProgress?(percent)
    }

    /// Only recompute match info when search parameters change
    private func updateMatchInfoIfNeeded(blocks: [MarkdownBlock]) {
        let searchKey = "\(searchText)-\(caseSensitive)-\(useRegex)"
        guard searchKey != lastSearchKey else { return }
        lastSearchKey = searchKey
        cachedMatchInfo = computeMatchInfo(blocks: blocks)
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

/// A chunk of blocks rendered together for large document virtualization.
/// Reduces LazyVStack item count from N to N/chunkSize.
private struct ChunkView: View {
    let blocks: [MarkdownBlock]
    let startIndex: Int
    let endIndex: Int
    var documentURL: URL? = nil
    var searchText: String = ""
    var cachedMatchInfo: MarkdownReaderViewWithAnchors.MatchInfo = .init()
    var currentMatchIndex: Int = 0
    var codeFontSize: CGFloat = 13
    var codeFontFamily: String? = nil
    var onTaskToggle: ((Int, Bool) -> Void)?
    var onMermaidExpand: ((String) -> Void)?

    /// Estimated total height for this chunk
    private var estimatedHeight: CGFloat {
        var total: CGFloat = 0
        for i in startIndex..<endIndex {
            total += blocks[i].estimatedHeight + 16 // Include spacing
        }
        return total
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(startIndex..<endIndex, id: \.self) { index in
                // Add match anchor if this block contains the current match
                if let matchIdx = cachedMatchInfo.blockToFirstMatch[index], matchIdx == currentMatchIndex {
                    Color.clear.frame(height: 0).id("match-\(currentMatchIndex)")
                }

                BlockView(
                    block: blocks[index],
                    documentURL: documentURL,
                    searchText: searchText,
                    matchRanges: cachedMatchInfo.blockMatches[index] ?? [],
                    codeFontSize: codeFontSize,
                    codeFontFamily: codeFontFamily,
                    onTaskToggle: onTaskToggle,
                    onMermaidExpand: onMermaidExpand
                )
                .id("block-\(index)")
            }
        }
        .frame(minHeight: estimatedHeight)
    }
}

/// Individual block view.
private struct BlockView: View {
    let block: MarkdownBlock
    var documentURL: URL? = nil
    var searchText: String = ""
    var matchRanges: [Range<String.Index>] = []
    var codeFontSize: CGFloat = 13
    var codeFontFamily: String? = nil
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
            CodeBlockView(data: codeData, fontSize: codeFontSize, fontFamily: codeFontFamily)

        case .image(let imageData):
            ImageBlockView(data: imageData, documentURL: documentURL)

        case .mermaid(let mermaidData):
            MermaidBlockView(data: mermaidData, onExpand: onMermaidExpand)

        case .mathBlock(let mathData):
            MathBlockView(latex: mathData.latex)
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
