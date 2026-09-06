import AppKit
import SwiftUI
import VoidReaderCore

enum LargeDocumentScrollAnchor {
    case top
    case center
}

struct LargeDocumentScrollRequest {
    let serial: Int
    let blockIndex: Int
    let anchor: LargeDocumentScrollAnchor
}

@MainActor
final class LargeDocumentNavigator: ObservableObject {
    @Published private(set) var request: LargeDocumentScrollRequest?
    private var serial = 0

    func scroll(to blockIndex: Int, anchor: LargeDocumentScrollAnchor) {
        serial &+= 1
        request = LargeDocumentScrollRequest(
            serial: serial,
            blockIndex: blockIndex,
            anchor: anchor
        )
    }
}

/// Renders markdown text as native SwiftUI content.
/// Uses LazyVStack for virtual scrolling performance on large documents.
struct MarkdownReaderView: View {
    let text: String
    var blocks: [MarkdownBlock] = []
    var documentURL: URL? = nil
    var codeFontSize: CGFloat = 13
    var codeFontFamily: String? = nil
    var onTaskToggle: ((UUID, Bool) -> Void)?
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
            // The collection uses its stable slot as identity. Calling
            // MarkdownBlock.id here hashes every text AttributedString on
            // every scroll-driven body update. Stateful children carry a
            // separate content identity so edit/reload still resets them.
            ForEach(Array(renderBlocks.enumerated()), id: \.offset) { index, block in
                blockView(for: block)
                    .padding(.top, BlockSpacing.topSpacing(at: index, in: renderBlocks))
                    .id(block.viewIdentity(slot: index))
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

        case .frontmatter(let fmData):
            FrontmatterBannerView(data: fmData)
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
    var contentGeneration: Int = 0
    var documentURL: URL? = nil
    var searchText: String = ""
    var caseSensitive: Bool = false
    var useRegex: Bool = false
    var currentMatchIndex: Int = 0
    var codeFontSize: CGFloat = 13
    var codeFontFamily: String? = nil
    var onTaskToggle: ((UUID, Bool) -> Void)?
    var onTopBlockChange: ((Int) -> Void)?
    var onMermaidExpand: ((String) -> Void)?
    var largeDocumentNavigator: LargeDocumentNavigator

    @Environment(\.documentHeightIndex) private var documentHeightIndex

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
        if renderBlocks.count > 1000, let documentHeightIndex {
            reusableContent(blocks: renderBlocks, heightIndex: documentHeightIndex)
                .onAppear {
                    DebugLog.log(.rendering, "Reusable content appearing: \(renderBlocks.count) blocks")
                }
        } else {
            directContent(blocks: renderBlocks)
        }
    }

    /// Architecture spike: keep the existing SwiftUI block renderers, but
    /// materialize only the rows near the AppKit scroll viewport. The canvas
    /// has stable document geometry from `DocumentHeightIndex`; individual
    /// `NSHostingView`s are created and discarded as their rows enter/leave
    /// an overscanned visible range.
    @ViewBuilder
    private func reusableContent(
        blocks renderBlocks: [MarkdownBlock],
        heightIndex: DocumentHeightIndex
    ) -> some View {
        ReusableBlockDocument(
            blocks: renderBlocks,
            contentGeneration: contentGeneration,
            heightIndex: heightIndex,
            documentURL: documentURL,
            highlighted: cachedMatchInfo.blockHighlighted,
            codeFontSize: codeFontSize,
            codeFontFamily: codeFontFamily,
            onTaskToggle: onTaskToggle,
            onTopBlockChange: onTopBlockChange,
            onMermaidExpand: onMermaidExpand,
            navigator: largeDocumentNavigator
        )
        .onAppear { setupState(blocks: renderBlocks) }
        .onChange(of: renderBlocks.count) { _, newCount in blockCount = newCount }
        .onChange(of: searchText) { _, _ in updateMatchInfoIfNeeded(blocks: renderBlocks) }
        .onChange(of: caseSensitive) { _, _ in updateMatchInfoIfNeeded(blocks: renderBlocks) }
        .onChange(of: useRegex) { _, _ in updateMatchInfoIfNeeded(blocks: renderBlocks) }
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

            ForEach(Array(renderBlocks.enumerated()), id: \.offset) { index, _ in
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
        .id(renderBlocks[index].viewIdentity(slot: index))
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

/// Experimental large-document canvas. This deliberately keeps the existing
/// block renderers; only ownership of viewport materialization moves to AppKit.
private struct ReusableBlockDocument: View {
    let blocks: [MarkdownBlock]
    let contentGeneration: Int
    @ObservedObject var heightIndex: DocumentHeightIndex
    let documentURL: URL?
    let highlighted: [Int: AttributedString]
    let codeFontSize: CGFloat
    let codeFontFamily: String?
    let onTaskToggle: ((UUID, Bool) -> Void)?
    let onTopBlockChange: ((Int) -> Void)?
    let onMermaidExpand: ((String) -> Void)?
    @ObservedObject var navigator: LargeDocumentNavigator

    @Environment(\.codeBlockMeasurementCache) private var codeBlockMeasurementCache
    @Environment(\.tableMeasurementCache) private var tableMeasurementCache
    @Environment(\.onImageExpand) private var onImageExpand
    @Environment(\.openURL) private var openURL

    var body: some View {
        ReusableBlockCanvasBridge(
            blocks: blocks,
            contentGeneration: contentGeneration,
            heightIndex: heightIndex,
            documentURL: documentURL,
            highlighted: highlighted,
            codeFontSize: codeFontSize,
            codeFontFamily: codeFontFamily,
            codeBlockMeasurementCache: codeBlockMeasurementCache,
            tableMeasurementCache: tableMeasurementCache,
            onImageExpand: onImageExpand,
            openURL: openURL,
            onTaskToggle: onTaskToggle,
            onTopBlockChange: onTopBlockChange,
            onMermaidExpand: onMermaidExpand,
            navigationRequest: navigator.request
        )
        .frame(height: max(1, heightIndex.totalHeight), alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReusableBlockCanvasBridge: NSViewRepresentable {
    let blocks: [MarkdownBlock]
    let contentGeneration: Int
    let heightIndex: DocumentHeightIndex
    let documentURL: URL?
    let highlighted: [Int: AttributedString]
    let codeFontSize: CGFloat
    let codeFontFamily: String?
    let codeBlockMeasurementCache: CodeBlockMeasurementCache?
    let tableMeasurementCache: TableMeasurementCache?
    let onImageExpand: ((ExpandedImageData) -> Void)?
    let openURL: OpenURLAction
    let onTaskToggle: ((UUID, Bool) -> Void)?
    let onTopBlockChange: ((Int) -> Void)?
    let onMermaidExpand: ((String) -> Void)?
    let navigationRequest: LargeDocumentScrollRequest?

    func makeNSView(context: Context) -> ReusableBlockCanvas {
        ReusableBlockCanvas()
    }

    func updateNSView(_ canvas: ReusableBlockCanvas, context: Context) {
        canvas.configure(
            blocks: blocks,
            contentGeneration: contentGeneration,
            heightIndex: heightIndex,
            documentURL: documentURL,
            highlighted: highlighted,
            codeFontSize: codeFontSize,
            codeFontFamily: codeFontFamily,
            codeBlockMeasurementCache: codeBlockMeasurementCache,
            tableMeasurementCache: tableMeasurementCache,
            onImageExpand: onImageExpand,
            openURL: openURL,
            onTaskToggle: onTaskToggle,
            onTopBlockChange: onTopBlockChange,
            onMermaidExpand: onMermaidExpand,
            navigationRequest: navigationRequest
        )
    }
}

/// A flipped document-space view which keeps only an overscanned slice of
/// SwiftUI block hosts alive and recycles hosts as the viewport moves.
private final class ReusableBlockCanvas: NSView {
    override var isFlipped: Bool { true }

    private var blocks: [MarkdownBlock] = []
    private var contentGeneration = -1
    private var heightIndex: DocumentHeightIndex?
    private var documentURL: URL?
    private var highlighted: [Int: AttributedString] = [:]
    private var codeFontSize: CGFloat = 13
    private var codeFontFamily: String?
    private var codeBlockMeasurementCache: CodeBlockMeasurementCache?
    private var tableMeasurementCache: TableMeasurementCache?
    private var onImageExpand: ((ExpandedImageData) -> Void)?
    private var openURL = OpenURLAction { _ in .systemAction }
    private var onTaskToggle: ((UUID, Bool) -> Void)?
    private var onTopBlockChange: ((Int) -> Void)?
    private var onMermaidExpand: ((String) -> Void)?
    private var hosts: [Int: NSHostingView<AnyView>] = [:]
    private var recycledHosts: [NSHostingView<AnyView>] = []
    private var boundsObserver: NSObjectProtocol?
    private weak var observedClipView: NSClipView?
    private var lastTopIndex = -1
    private var pendingTopIndex: Int?
    private var topReportWorkItem: DispatchWorkItem?
    private var lastNavigationSerial = -1
    private var preparedGeneration = -1
    private var preparedWidth: CGFloat = 0
    private var heightPreparationTask: Task<Void, Never>?

    deinit {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        heightPreparationTask?.cancel()
        topReportWorkItem?.cancel()
    }

    func configure(
        blocks: [MarkdownBlock],
        contentGeneration: Int,
        heightIndex: DocumentHeightIndex,
        documentURL: URL?,
        highlighted: [Int: AttributedString],
        codeFontSize: CGFloat,
        codeFontFamily: String?,
        codeBlockMeasurementCache: CodeBlockMeasurementCache?,
        tableMeasurementCache: TableMeasurementCache?,
        onImageExpand: ((ExpandedImageData) -> Void)?,
        openURL: OpenURLAction,
        onTaskToggle: ((UUID, Bool) -> Void)?,
        onTopBlockChange: ((Int) -> Void)?,
        onMermaidExpand: ((String) -> Void)?,
        navigationRequest: LargeDocumentScrollRequest?
    ) {
        let contentChanged = self.contentGeneration != contentGeneration
        let populationChanged = self.blocks.count != blocks.count
        self.blocks = blocks
        self.contentGeneration = contentGeneration
        self.heightIndex = heightIndex
        self.documentURL = documentURL
        self.highlighted = highlighted
        self.codeFontSize = codeFontSize
        self.codeFontFamily = codeFontFamily
        self.codeBlockMeasurementCache = codeBlockMeasurementCache
        self.tableMeasurementCache = tableMeasurementCache
        self.onImageExpand = onImageExpand
        self.openURL = openURL
        self.onTaskToggle = onTaskToggle
        self.onTopBlockChange = onTopBlockChange
        self.onMermaidExpand = onMermaidExpand

        if populationChanged {
            recycleAllHosts()
        } else if contentChanged {
            // A document edit can replace content without changing its block
            // count. Refresh only the bounded live population.
            for (index, host) in hosts {
                host.rootView = rootView(at: index)
            }
        }
        installScrollObservationIfNeeded()
        refreshViewport()
        applyNavigationRequest(navigationRequest)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.installScrollObservationIfNeeded()
            self?.refreshViewport()
        }
    }

    override func layout() {
        super.layout()
        refreshViewport()
    }

    private func installScrollObservationIfNeeded() {
        guard let clipView = enclosingScrollView?.contentView,
              observedClipView !== clipView else { return }
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
        observedClipView = clipView
        clipView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            self?.refreshViewport()
        }
    }

    private func refreshViewport() {
        guard !blocks.isEmpty,
              bounds.width > 0,
              let heightIndex,
              let scrollView = enclosingScrollView,
              let documentView = scrollView.documentView else { return }

        let visible = convert(scrollView.documentVisibleRect, from: documentView)
        prepareHeightsIfNeeded(width: bounds.width)
        let overscan: CGFloat = 1_200
        let lowerY = max(0, visible.minY - overscan)
        let upperY = min(bounds.height, visible.maxY + overscan)
        let first = heightIndex.blockIndex(atOffset: lowerY)
        let last = heightIndex.blockIndex(atOffset: upperY)
        let wanted = max(0, first - 2)...min(blocks.count - 1, last + 2)

        for index in hosts.keys.filter({ !wanted.contains($0) }) {
            guard let host = hosts.removeValue(forKey: index) else { continue }
            recycle(host)
        }

        for index in wanted {
            let host = hosts[index] ?? makeHost(at: index)
            hosts[index] = host
            let spacing = BlockSpacing.topSpacing(at: index, in: blocks)
            let rowTop = heightIndex.offset(beforeBlock: index)
            let rowBottom = heightIndex.offset(beforeBlock: index + 1)
            host.frame = NSRect(
                x: 0,
                y: rowTop + spacing,
                width: bounds.width,
                height: max(1, rowBottom - rowTop - spacing)
            )
        }

        let top = heightIndex.blockIndex(atOffset: max(0, visible.minY))
        if top != lastTopIndex {
            lastTopIndex = top
            scheduleTopBlockReport(top)
        }
    }

    private func scheduleTopBlockReport(_ index: Int) {
        pendingTopIndex = index
        guard topReportWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let pendingTopIndex = self.pendingTopIndex else { return }
            self.pendingTopIndex = nil
            self.topReportWorkItem = nil
            self.onTopBlockChange?(pendingTopIndex)
        }
        topReportWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func makeHost(at index: Int) -> NSHostingView<AnyView> {
        let host = recycledHosts.popLast()
            ?? NSHostingView(rootView: AnyView(EmptyView()))
        host.rootView = rootView(at: index)
        addSubview(host)
        return host
    }

    private func rootView(at index: Int) -> AnyView {
        let content = BlockView(
            block: blocks[index],
            documentURL: documentURL,
            highlighted: highlighted[index],
            codeFontSize: codeFontSize,
            codeFontFamily: codeFontFamily,
            onTaskToggle: onTaskToggle,
            onMermaidExpand: onMermaidExpand
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.codeBlockMeasurementCache, codeBlockMeasurementCache)
        .environment(\.tableMeasurementCache, tableMeasurementCache)
        .environment(\.onImageExpand, onImageExpand)
        .environment(\.openURL, openURL)

        return AnyView(content)
    }

    private func prepareHeightsIfNeeded(width: CGFloat) {
        let roundedWidth = width.rounded()
        guard contentGeneration != preparedGeneration
                || abs(roundedWidth - preparedWidth) >= 1 else { return }

        preparedGeneration = contentGeneration
        preparedWidth = roundedWidth
        heightPreparationTask?.cancel()
        let generation = contentGeneration
        let snapshot = blocks
        let font = CodeBlockView.nsFont(family: codeFontFamily, size: codeFontSize)
        let start = CFAbsoluteTimeGetCurrent()

        heightPreparationTask = Task { [weak self] in
            let heights = await Task.detached(priority: .userInitiated) {
                DocumentBlockMeasurement.heights(
                    for: snapshot,
                    width: roundedWidth,
                    codeFont: font
                )
            }.value
            guard !Task.isCancelled else { return }
            self?.applyPreparedHeights(
                heights,
                generation: generation,
                elapsed: CFAbsoluteTimeGetCurrent() - start
            )
        }
    }

    private func applyPreparedHeights(
        _ measurements: [Int: CGFloat],
        generation: Int,
        elapsed: TimeInterval
    ) {
        guard generation == contentGeneration,
              let heightIndex,
              let scrollView = enclosingScrollView,
              let documentView = scrollView.documentView else { return }

        let visibleBefore = convert(scrollView.documentVisibleRect, from: documentView)
        let anchorIndex = heightIndex.blockIndex(atOffset: max(0, visibleBefore.minY))
        let offsetWithinAnchor = visibleBefore.minY - heightIndex.offset(beforeBlock: anchorIndex)
        guard heightIndex.recordHeights(measurements) else { return }

        DebugLog.log(
            .rendering,
            "Prepared \(measurements.count) block heights in \(String(format: "%.2f", elapsed * 1000))ms totalHeight=\(Int(heightIndex.totalHeight))"
        )
        needsLayout = true

        DispatchQueue.main.async { [weak self, weak scrollView] in
            guard let self,
                  let scrollView,
                  let documentView = scrollView.documentView,
                  let heightIndex = self.heightIndex else { return }
            let visibleAfter = self.convert(scrollView.documentVisibleRect, from: documentView)
            let desiredY = heightIndex.offset(beforeBlock: anchorIndex) + offsetWithinAnchor
            let clipView = scrollView.contentView
            var origin = clipView.bounds.origin
            origin.y += desiredY - visibleAfter.minY
            let maximumY = max(0, documentView.bounds.height - clipView.bounds.height)
            origin.y = min(maximumY, max(0, origin.y))
            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)
            self.refreshViewport()
        }
    }

    private func recycle(_ host: NSHostingView<AnyView>) {
        host.removeFromSuperview()
        host.rootView = AnyView(EmptyView())
        if recycledHosts.count < 64 {
            recycledHosts.append(host)
        }
    }

    private func recycleAllHosts() {
        let live = Array(hosts.values)
        hosts.removeAll(keepingCapacity: true)
        live.forEach(recycle)
    }

    private func applyNavigationRequest(_ request: LargeDocumentScrollRequest?) {
        guard let request,
              request.serial != lastNavigationSerial,
              !blocks.isEmpty,
              let heightIndex,
              let scrollView = enclosingScrollView,
              let documentView = scrollView.documentView else { return }

        let index = max(0, min(request.blockIndex, blocks.count - 1))
        let visible = convert(scrollView.documentVisibleRect, from: documentView)
        let rowTop = heightIndex.offset(beforeBlock: index)
        let rowBottom = heightIndex.offset(beforeBlock: index + 1)
        let desiredCanvasY: CGFloat
        switch request.anchor {
        case .top:
            desiredCanvasY = rowTop
        case .center:
            desiredCanvasY = (rowTop + rowBottom - visible.height) / 2
        }

        let delta = desiredCanvasY - visible.minY
        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        let maximumY = max(0, documentView.bounds.height - clipView.bounds.height)
        origin.y = min(maximumY, max(0, origin.y + delta))
        lastNavigationSerial = request.serial
        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)
        refreshViewport()
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
    var onTaskToggle: ((UUID, Bool) -> Void)?
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
            // `offset` is slice-local (0-based); global index is `startIndex + offset`.
            ForEach(Array(blocks[startIndex..<endIndex].enumerated()), id: \.offset) { offset, _ in
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
                .id(blocks[index].viewIdentity(slot: index))
            }
        }
        .frame(minHeight: estimatedHeight)
    }
}

private extension MarkdownBlock {
    /// Cheap SwiftUI identity for a block at a document slot. Text has no
    /// child-local state, so its slot is sufficient and its value updates in
    /// place. Stateful block kinds include their parse-time UUID so a reload
    /// cannot reuse highlighting, measurement, or web content from the old
    /// block at the same slot.
    func viewIdentity(slot: Int) -> String {
        switch self {
        case .text:
            return "text-\(slot)"
        case .table(let data):
            return "table-\(data.id)"
        case .taskList(let items):
            return "tasklist-\(items.first?.id.uuidString ?? "empty")-\(items.count)"
        case .codeBlock(let data):
            return "code-\(data.id)"
        case .image(let data):
            return "image-\(data.id)"
        case .mermaid(let data):
            return "mermaid-\(data.id)"
        case .mathBlock(let data):
            return "math-\(data.id)"
        case .frontmatter(let data):
            return "frontmatter-\(data.id)"
        }
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
    var onTaskToggle: ((UUID, Bool) -> Void)?
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

        case .frontmatter(let fmData):
            FrontmatterBannerView(data: fmData)
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
