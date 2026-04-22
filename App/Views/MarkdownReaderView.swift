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
        #if DEBUG
        let _ = InvalidationCounter.tick("MarkdownReaderView")
        #endif
        // Use provided blocks or render if empty (fallback for previews)
        let renderBlocks = blocks.isEmpty ? BlockRenderer.render(text) : blocks

        // `spacing: 0` at the LazyVStack level; per-row top padding adds 16pt
        // between ordinary blocks but 0 between same-group code segments,
        // so a segmented code block renders with no visible seams.
        LazyVStack(alignment: .leading, spacing: 0) {
            // Identity tracks block.id, not index. Index-based identity
            // caused SwiftUI to reuse CodeBlockView @State (highlighted +
            // measurement caches) across different blocks when the block
            // list regenerated on edit/reload/settings change.
            ForEach(Array(renderBlocks.enumerated()), id: \.element.id) { index, block in
                blockView(for: block)
                    .padding(.top, BlockSpacing.topSpacing(at: index, in: renderBlocks))
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

/// Efficient scroll position tracker using periodic sampling instead of per-frame updates.
/// This approach avoids the jank caused by onChange(of: geo.frame...) firing every frame.
struct ScrollPositionTracker: View {
    let coordinateSpace: String
    let blockCount: Int
    let onPositionUpdate: (Int, Int) -> Void

    @State private var lastReportedPercent: Int = -1
    @State private var hasReportedInitial: Bool = false

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    reportInitialPosition(from: geo)
                }
                // Use preference key for efficient position tracking
                .preference(
                    key: ScrollOffsetPreferenceKey.self,
                    value: -geo.frame(in: .named(coordinateSpace)).minY
                )
        }
        .frame(height: 0)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            // Preference changes are batched by SwiftUI, more efficient than onChange
            calculateAndReport(offset: offset)
        }
    }

    private func reportInitialPosition(from geo: GeometryProxy) {
        guard !hasReportedInitial else { return }
        hasReportedInitial = true
        let offset = -geo.frame(in: .named(coordinateSpace)).minY
        calculateAndReport(offset: offset, force: true)
    }

    private func calculateAndReport(offset: CGFloat, force: Bool = false) {
        guard blockCount > 0 else { return }

        let estimatedBlockHeight: CGFloat = 60
        let estimatedIndex = max(0, min(blockCount - 1, Int(offset / estimatedBlockHeight)))
        let percent = blockCount > 1 ? (estimatedIndex * 100) / (blockCount - 1) : 0
        let clampedPercent = min(100, max(0, percent))

        // Only report if percent changed (avoids redundant updates), or forced
        if force || clampedPercent != lastReportedPercent {
            lastReportedPercent = clampedPercent
            onPositionUpdate(estimatedIndex, clampedPercent)
        }
    }
}

/// Preference key for scroll offset - batched updates are more efficient
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Block-to-block vertical spacing rules. Centralizes the "collapse spacing
/// between same-group segments" decision so every LazyVStack/VStack path in
/// the reader agrees, and so the scroll-percent math can mirror it via
/// `DocumentHeightIndex`'s spacing provider.
enum BlockSpacing {
    /// Inter-block spacing used by the reader's `LazyVStack` rows.
    static let interBlock: CGFloat = 16

    /// Top padding for block at `index`. Returns 0 for the first block
    /// (nothing above it) and for any code segment that continues the
    /// previous block's segmentation group; returns `interBlock` otherwise.
    static func topSpacing(at index: Int, in blocks: [MarkdownBlock]) -> CGFloat {
        guard index > 0 else { return 0 }
        if case .codeBlock(let curr) = blocks[index],
           case .codeBlock(let prev) = blocks[index - 1],
           let a = curr.segment, let b = prev.segment,
           a.groupID == b.groupID {
            return 0
        }
        return interBlock
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
        // Same pattern as `MarkdownReaderView.body`: spacing at the stack
        // level is 0 so segmented code blocks can collapse their inter-row
        // gap; `BlockSpacing.topSpacing` adds 16pt everywhere else.
        LazyVStack(alignment: .leading, spacing: 0) {
            // Scroll tracker at top of content
            scrollTracker

            // Identity tracks block.id, not index — see MarkdownReaderView.body.
            ForEach(Array(renderBlocks.enumerated()), id: \.element.id) { index, _ in
                blockContent(at: index, in: renderBlocks)
                    .padding(.top, BlockSpacing.topSpacing(at: index, in: renderBlocks))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            // Scroll tracker at top of content
            scrollTracker

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
            highlighted: cachedMatchInfo.blockHighlighted[index],
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

    /// Scroll tracker using efficient PreferenceKey-based position detection.
    /// Only reports when percentage actually changes.
    @ViewBuilder
    private var scrollTracker: some View {
        if blockCount > 0 {
            ScrollPositionTracker(
                coordinateSpace: "reader-scroll",
                blockCount: blockCount,
                onPositionUpdate: handleScrollUpdate
            )
            // Force recreation when blockCount changes to trigger onAppear
            .id("scroll-tracker-\(blockCount)")
        }
    }

    /// Handle scroll position update for outline sync
    private func handleScrollUpdate(blockIndex: Int, percent: Int) {
        guard blockIndex != lastReportedBlockIndex else { return }
        lastReportedBlockIndex = blockIndex
        onTopBlockChange?(blockIndex)
        // Note: onScrollProgress is now handled by ContentView's scroll tracker
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
        /// Pre-built highlighted copy of each block's AttributedString. Populated
        /// once per search-key change so `BlockView.body` becomes a pure
        /// `Text(cached)` read instead of rebuilding highlights on every
        /// SwiftUI re-evaluation (which happens per arrow-key match navigation).
        var blockHighlighted: [Int: AttributedString] = [:]
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
                let ranges = matches.map { $0.range }
                info.blockMatches[blockIdx] = ranges
                info.blockToFirstMatch[blockIdx] = globalMatchIndex
                info.blockHighlighted[blockIdx] = Self.buildHighlighted(
                    original: attrString,
                    originalText: blockText,
                    matchRanges: ranges
                )
                globalMatchIndex += matches.count
            }
        }

        return info
    }

    /// Builds a highlighted `AttributedString` in a single forward pass.
    ///
    /// The old approach did `distance(from: startIndex, to: range.lowerBound)`
    /// per match — O(N) per match, O(M·N) per block — and ran inside
    /// `BlockView.body` on every re-render. This version walks both the
    /// source `String` and the mutable `AttributedString` cursor forward in
    /// lockstep, so each character is visited at most twice total regardless
    /// of match count. Called once per search-key change; the result is
    /// cached in `MatchInfo.blockHighlighted`.
    private static func buildHighlighted(
        original: AttributedString,
        originalText: String,
        matchRanges: [Range<String.Index>]
    ) -> AttributedString {
        var result = original
        var attrCursor = result.startIndex
        var textCursor = originalText.startIndex

        for range in matchRanges {
            // Advance to match start (cursor-relative, not from startIndex).
            let preSpan = originalText.distance(from: textCursor, to: range.lowerBound)
            let matchStart = result.index(attrCursor, offsetByCharacters: preSpan)

            // Advance to match end.
            let matchSpan = originalText.distance(from: range.lowerBound, to: range.upperBound)
            let matchEnd = result.index(matchStart, offsetByCharacters: matchSpan)

            result[matchStart..<matchEnd].backgroundColor = .yellow
            result[matchStart..<matchEnd].foregroundColor = .black

            attrCursor = matchEnd
            textCursor = range.upperBound
        }

        return result
    }

    /// Finds which block contains the given heading text.
    /// Uses exact match first (headings are isolated in their own blocks),
    /// then falls back to prefix match for robustness.
    static func blockIndex(for headingText: String, in blocks: [MarkdownBlock]) -> Int? {
        let target = headingText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Exact match — headings get their own block via flushTextBuffer()
        for (idx, block) in blocks.enumerated() {
            if case .text(let attr) = block {
                let blockText = String(attr.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if blockText == target {
                    return idx
                }
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
            let spacing = BlockSpacing.topSpacing(at: i, in: blocks)
            total += blocks[i].estimatedHeight + spacing
        }
        return total
    }

    var body: some View {
        // `spacing: 0` + per-row top padding: identical scheme to
        // `directContent` so segmented code blocks stay seamless across
        // chunk boundaries as well.
        VStack(alignment: .leading, spacing: 0) {
            // Identity tracks block.id, not slot index — see MarkdownReaderView.body.
            // `offset` is slice-local (0-based); global index is `startIndex + offset`.
            ForEach(Array(blocks[startIndex..<endIndex].enumerated()), id: \.element.id) { offset, _ in
                let index = startIndex + offset
                // Add match anchor if this block contains the current match
                if let matchIdx = cachedMatchInfo.blockToFirstMatch[index], matchIdx == currentMatchIndex {
                    Color.clear.frame(height: 0).id("match-\(currentMatchIndex)")
                }

                BlockView(
                    block: blocks[index],
                    documentURL: documentURL,
                    highlighted: cachedMatchInfo.blockHighlighted[index],
                    codeFontSize: codeFontSize,
                    codeFontFamily: codeFontFamily,
                    onTaskToggle: onTaskToggle,
                    onMermaidExpand: onMermaidExpand
                )
                .padding(.top, BlockSpacing.topSpacing(at: index, in: blocks))
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
    /// Pre-highlighted copy of the block's text, when there are matches to
    /// highlight. Built once per search-key change in `computeMatchInfo`, so
    /// this closure just picks between the cached highlight and the plain
    /// text — no per-render string/index walking.
    var highlighted: AttributedString? = nil
    var codeFontSize: CGFloat = 13
    var codeFontFamily: String? = nil
    var onTaskToggle: ((Int, Bool) -> Void)?
    var onMermaidExpand: ((String) -> Void)?

    var body: some View {
        #if DEBUG
        let _ = InvalidationCounter.tick("BlockView")
        #endif
        switch block {
        case .text(let attributedString):
            Text(highlighted ?? attributedString)
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
