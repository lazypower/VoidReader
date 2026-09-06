import SwiftUI
import VoidReaderCore
import Combine
import AppKit

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @State private var isEditMode = false
    @AppStorage("showStatusBar") private var showStatusBar = true
    @AppStorage("showOutlineSidebar") private var showOutlineSidebar = false
    @SceneStorage("editorSplitFraction") private var editorSplitFraction: Double = 0.5
    @AppStorage("readerFontSize") private var readerFontSize: Double = 16.0
    @AppStorage("readerFontFamily") private var readerFontFamily: String = ""
    @AppStorage("codeFontFamily") private var codeFontFamily: String = ""
    @AppStorage("fullWidthReader") private var fullWidthReader: Bool = false
    @AppStorage("selectedThemeID") private var selectedThemeID: String = "system"
    @AppStorage("applyThemeToReader") private var applyThemeToReader: Bool = false
    @AppStorage("appearanceOverride") private var appearanceOverride: String = "system"

    // Formatting settings
    @AppStorage("formatOnSave") private var formatOnSave: Bool = false
    @AppStorage("listMarkerStyle") private var listMarkerStyle: String = "-"
    @AppStorage("emphasisMarkerStyle") private var emphasisMarkerStyle: String = "*"
    @AppStorage("disabledLintRules") private var disabledLintRules: String = ""

    @Environment(\.colorScheme) private var systemColorScheme
    @State private var showCheatSheet = false
    @State private var isDistractionFree = false
    @State private var documentStats: DocumentStats
    @State private var debouncedText: String
    @FocusState private var isEditorFocused: Bool

    // Outline sidebar
    @State private var headings: [HeadingInfo] = []
    @State private var selectedHeadingID: UUID?
    @State private var scrollToHeadingIndex: Int?
    @State private var headingLocations: [(heading: HeadingInfo, blockIndex: Int)] = []

    // Debounce publisher for preview updates
    @State private var textUpdatePublisher = PassthroughSubject<String, Never>()
    @State private var cancellables = Set<AnyCancellable>()

    // For print/export/share/format commands
    /// This document's own window, so print/export can act only when it's front.
    @State private var hostWindow: NSWindow?
    private let printPublisher = NotificationCenter.default.publisher(for: .printDocument)
    private let exportPDFPublisher = NotificationCenter.default.publisher(for: .exportPDF)
    private let sharePublisher = NotificationCenter.default.publisher(for: .shareDocument)
    private let formatDocumentPublisher = NotificationCenter.default.publisher(for: .formatDocument)
    private let reloadFromDiskPublisher = NotificationCenter.default.publisher(for: .reloadFromDisk)

    // Share sheet state
    @State private var showingShare = false

    // Scroll position tracking
    @State private var hasRestoredScroll = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var savedScrollBlockIndex: Int?
    @State private var currentTopBlockIndex: Int = 0
    @State private var displayedPercentRead: Int = 0
    @State private var scrollOffsetForPercent: CGFloat = 0
    @State private var scrollFractionForPersistence: Double = 0

    // Find bar
    @State private var showFindBar = false
    @State private var showReplace = false
    @State private var searchText = ""
    @State private var replaceText = ""
    @State private var caseSensitive = false
    @State private var useRegex = false
    @State private var searchMatches: [TextSearcher.Match] = []
    /// Advances for every completed query, even when consecutive queries
    /// happen to return the same number of matches.
    @State private var searchResultGeneration = 0
    /// Captured substrings for each match, parallel to `searchMatches`. Populated
    /// once per search update so `currentMatchText` is a cheap array index
    /// instead of re-searching `document.text` on every SwiftUI re-render.
    @State private var matchTexts: [String] = []
    @State private var currentMatchIndex = 0

    // Cached rendered blocks (expensive to compute)
    @State private var renderedBlocks: [MarkdownBlock] = []
    @State private var renderedBlocksGeneration: Int = 0
    @State private var isRendering = false
    @State private var renderTask: Task<Void, Never>?
    /// Guard for the `firstPaint` signpost event so it fires exactly once per
    /// document-open lifecycle. Reset to false in `reloadFromDisk()` so the next paint
    /// after a reload re-fires it (paired with the `reloadFromDisk` interval).
    @State private var firstPaintFired = false

    /// Document-scoped cache of TextKit-measured `(attributed, height)`
    /// for large code blocks. Populated off-main by `prefetchCodeBlockMeasurements`
    /// as soon as blocks arrive from the parser, and injected into the
    /// reader view tree via environment. Cleared on document change.
    @State private var codeBlockMeasurementCache = CodeBlockMeasurementCache()

    /// Document-scoped cache of measured column widths / row heights for
    /// large tables. Populated off-main by `prefetchTableMeasurements`
    /// as soon as blocks arrive, and injected into the reader view tree via
    /// environment. Cleared on document change. Mirrors the code-block
    /// measurement cache pattern.
    @State private var tableMeasurementCache = TableMeasurementCache()

    /// Document-wide block-height index used to map saved scroll fractions
    /// back to block anchors. The live percentage itself comes directly from
    /// NSScrollView, whose scrollable range is exact after layout.
    @StateObject private var documentHeightIndex = DocumentHeightIndex()
    @StateObject private var largeDocumentNavigator = LargeDocumentNavigator()

    // Lint warnings
    @State private var lintWarnings: [LintWarning] = []
    @State private var lintUpdatePublisher = PassthroughSubject<String, Never>()

    // Search debouncing
    @State private var searchUpdatePublisher = PassthroughSubject<Void, Never>()

    // Mermaid expand overlay
    @State private var expandedMermaidSource: String?

    // Image expand overlay
    @State private var expandedImageData: ExpandedImageData?

    // File watching and conflict detection
    @State private var fileWatcher: FileWatcher?
    @State private var lastKnownModDate: Date?
    @State private var showExternalChangeAlert = false
    @State private var suppressExternalChangeAlert = false
    @State private var showSaveConflictAlert = false
    @State private var pendingSaveAction: (() -> Void)?

    init(document: Binding<MarkdownDocument>, fileURL: URL? = nil) {
        self._document = document
        self.fileURL = fileURL
        self._documentStats = State(initialValue: DocumentStats(text: document.wrappedValue.text))
        self._debouncedText = State(initialValue: document.wrappedValue.text)
    }

    var body: some View {
        #if DEBUG
        let _ = InvalidationCounter.tick("ContentView")
        #endif
        Group {
            if isDistractionFree {
                DistractionFreeView(
                    document: $document,
                    isActive: $isDistractionFree,
                    isEditMode: isEditMode
                )
                .transition(.opacity)
            } else {
                normalView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isDistractionFree)
        .frame(minWidth: 600, minHeight: 400)
        .overlay {
            if showCheatSheet {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    GFMCheatSheetView()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showCheatSheet)
        .overlay {
            if let source = expandedMermaidSource {
                MermaidExpandedOverlay(
                    source: source,
                    isPresented: Binding(
                        get: { expandedMermaidSource != nil },
                        set: { if !$0 { expandedMermaidSource = nil } }
                    )
                )
                .transition(.opacity)
            } else if let imageData = expandedImageData {
                ImageExpandedOverlay(
                    image: imageData.image,
                    altText: imageData.altText,
                    isPresented: Binding(
                        get: { expandedImageData != nil },
                        set: { if !$0 { expandedImageData = nil } }
                    )
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expandedMermaidSource != nil || expandedImageData != nil)
        .overlay(alignment: .topLeading) {
            // Frame drop monitor for XCUITest performance tests (debug only)
            if ProcessInfo.processInfo.environment["VOID_READER_DEBUG"] != nil {
                FrameDropOverlay()
            }
        }
        .cheatSheetOnHold(isShowing: $showCheatSheet)
        .onAppear {
            // Signpost: openDocument interval — spans the .onAppear setup work.
            // Ends after the initial render handoff (sync path returns or progressive path
            // assigns initialBlocks); see Signposts.lifecycle docstring for boundaries.
            let signposter = Signposts.signposter(for: .lifecycle)
            let bytes = document.text.utf8.count
            let ext = fileURL?.pathExtension ?? ""
            let state = signposter.beginInterval(
                "openDocument",
                id: signposter.makeSignpostID(),
                "bytes=\(bytes) ext=\(ext)"
            )
            defer { signposter.endInterval("openDocument", state) }

            DebugLog.info(.lifecycle, "ContentView.onAppear - \(fileURL?.lastPathComponent ?? "untitled") (\(document.text.count) chars)")
            #if DEBUG
            // DIAGNOSTIC: confirm whether signposts are enabled at runtime.
            DebugLog.info(.lifecycle, "Signposts.lifecycle.isEnabled=\(Signposts.lifecycle.isEnabled) rendering.isEnabled=\(Signposts.rendering.isEnabled)")
            #endif
            DebugLog.logMemory(.lifecycle, context: "Document open")
            setupDebouncing()
            updateHeadings(from: document.text)
            updateRenderedBlocks(from: document.text)
            setupFileWatcher()
        }
        .onChange(of: document.text) { _, newValue in
            // Send to debounce publisher for expensive operations
            textUpdatePublisher.send(newValue)
            // Update stats immediately (cheap operation)
            documentStats = DocumentStats(text: newValue)
            // Send to lint debouncer (500ms)
            lintUpdatePublisher.send(newValue)
        }
        .onDisappear {
            Signposts.interval("closeDocument", category: .lifecycle) {
                fileWatcher?.stop()
            }
        }
        .alert("File Changed", isPresented: $showExternalChangeAlert) {
            Button("Reload") { reloadFromDisk() }
            Button("Keep My Version", role: .cancel) {
                // Update our known mod date to avoid repeated alerts
                lastKnownModDate = fileURL?.fileModificationDate
            }
        } message: {
            Text("This file has been modified by another application. Would you like to reload it?")
        }
        .alert("Save Conflict", isPresented: $showSaveConflictAlert) {
            Button("Overwrite", role: .destructive) {
                pendingSaveAction?()
                pendingSaveAction = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSaveAction = nil
            }
        } message: {
            Text("This file has been modified by another application since you opened it. Overwrite with your changes?")
        }
        .background(WindowAccessor { hostWindow = $0 })
        .onReceive(printPublisher) { _ in
            printDocument()
        }
        .onReceive(exportPDFPublisher) { _ in
            exportPDF()
        }
        .onReceive(sharePublisher) { _ in
            showingShare = true
        }
        .onReceive(formatDocumentPublisher) { _ in
            formatDocument()
        }
        .onReceive(reloadFromDiskPublisher) { _ in
            reloadFromDisk()
        }
        .onChange(of: searchText) { _, _ in
            searchUpdatePublisher.send()
        }
        .onChange(of: caseSensitive) { _, _ in
            searchUpdatePublisher.send()
        }
        .onChange(of: useRegex) { _, _ in
            searchUpdatePublisher.send()
        }
        .onChange(of: renderTrigger) { _, _ in
            updateRenderedBlocks(from: document.text)
        }
        .background(ShareSheetPresenter(isPresented: $showingShare, items: [document.text]))
        .background(keyboardShortcuts)
        .onExitCommand {
            if showFindBar {
                dismissFindBar()
            }
        }
    }

    // MARK: - Print & Export

    private func printDocument() {
        // Only the front (key) window's ContentView acts. The print/export
        // commands post a GLOBAL notification that every open window receives,
        // so without this each open document ran its own modal print panel —
        // stacking unclosable grey dialogs that wedged the app.
        guard let window = hostWindow, window.isKeyWindow else { return }
        DocumentPrinter.print(text: document.text, documentURL: fileURL, from: window)
    }

    private func exportPDF() {
        guard let window = hostWindow, window.isKeyWindow else { return }
        // Use document title or fallback
        let suggestedName = fileURL?.deletingPathExtension().lastPathComponent ?? "Document"
        DocumentPrinter.exportPDF(text: document.text, documentURL: fileURL, suggestedName: suggestedName, from: window)
    }

    // MARK: - Font Size

    private static let minFontSize: Double = 10
    private static let maxFontSize: Double = 32
    private static let defaultFontSize: Double = 16
    private static let fontSizeStep: Double = 2

    private var renderStyle: MarkdownRenderer.Style {
        var style = MarkdownRenderer.Style()
        style.bodySize = CGFloat(readerFontSize)
        style.codeSize = CGFloat(readerFontSize * 0.875) // Code slightly smaller

        // Set font families (empty string = system font)
        if !readerFontFamily.isEmpty {
            style.fontFamily = readerFontFamily
        }
        if !codeFontFamily.isEmpty {
            style.codeFontFamily = codeFontFamily
        }

        // Apply theme colors to reader only if enabled (editor always uses theme)
        if applyThemeToReader && !currentTheme.isSystemTheme {
            let palette = currentTheme.palette(for: effectiveColorScheme)
            style.textColor = palette.text
            style.secondaryColor = palette.subtext0
            style.linkColor = palette.blue
            style.codeBackground = palette.surface0.opacity(0.5)
            style.headingColor = palette.mauve
            style.listMarkerColor = palette.teal
            style.blockquoteColor = palette.lavender
            style.mathColor = palette.green
        }
        // When disabled or System theme, leave colors as nil to use semantic macOS colors

        return style
    }

    /// Resolved code font family name (nil = system mono)
    private var resolvedCodeFontFamily: String? {
        codeFontFamily.isEmpty ? nil : codeFontFamily
    }

    // MARK: - Theme

    /// Current theme from registry
    private var currentTheme: AppTheme {
        ThemeRegistry.shared.themeOrDefault(id: selectedThemeID)
    }

    /// Effective color scheme (respects appearance override)
    private var effectiveColorScheme: ColorScheme {
        switch appearanceOverride {
        case "light": return .light
        case "dark": return .dark
        default: return systemColorScheme
        }
    }

    /// Combined trigger for re-rendering (consolidates multiple onChange handlers)
    private var renderTrigger: String {
        "\(readerFontFamily)-\(readerFontSize)-\(codeFontFamily)-\(selectedThemeID)-\(applyThemeToReader)-\(systemColorScheme)-\(appearanceOverride)"
    }

    private func increaseFontSize() {
        readerFontSize = min(readerFontSize + Self.fontSizeStep, Self.maxFontSize)
        // renderTrigger onChange handles updateRenderedBlocks
    }

    private func decreaseFontSize() {
        readerFontSize = max(readerFontSize - Self.fontSizeStep, Self.minFontSize)
        // renderTrigger onChange handles updateRenderedBlocks
    }

    private func resetFontSize() {
        readerFontSize = Self.defaultFontSize
        // renderTrigger onChange handles updateRenderedBlocks
    }

    @ViewBuilder
    private var keyboardShortcuts: some View {
        // Find/Replace shortcuts
        Group {
            Button("") { showFind() }
                .keyboardShortcut("f", modifiers: .command)
            Button("") { showFindAndReplace() }
                .keyboardShortcut("h", modifiers: .command)
        }
        .hidden()

        // Font size shortcuts
        Group {
            Button("") { increaseFontSize() }
                .keyboardShortcut("+", modifiers: .command)
            Button("") { increaseFontSize() }
                .keyboardShortcut("=", modifiers: .command)
            Button("") { decreaseFontSize() }
                .keyboardShortcut("-", modifiers: .command)
            Button("") { resetFontSize() }
                .keyboardShortcut("0", modifiers: .command)
        }
        .hidden()
    }

    private var normalView: some View {
        HStack(spacing: 0) {
            // Outline sidebar
            if showOutlineSidebar {
                OutlineSidebarView(
                    headings: headings,
                    onHeadingTap: scrollToHeading,
                    currentHeadingID: selectedHeadingID
                )
                .transition(.move(edge: .leading))

                Divider()
            }

            // Main content area
            VStack(spacing: 0) {
                // Find bar
                if showFindBar {
                    FindBarView(
                        isVisible: $showFindBar,
                        searchText: $searchText,
                        replaceText: $replaceText,
                        caseSensitive: $caseSensitive,
                        useRegex: $useRegex,
                        matchCount: searchMatches.count,
                        currentMatch: searchMatches.isEmpty ? 0 : currentMatchIndex + 1,
                        currentMatchText: currentMatchText,
                        isEditMode: isEditMode,
                        showReplace: showReplace,
                        onNext: findNext,
                        onPrevious: findPrevious,
                        onReplace: replaceCurrent,
                        onReplaceAll: replaceAll,
                        onDismiss: dismissFindBar
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Main content
                Group {
                    if document.text.isEmpty && !isEditMode {
                        editorView
                            .onAppear {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditMode = true
                                }
                            }
                    } else if isEditMode {
                        editorView
                    } else {
                        readerView
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isEditMode)

                // Status bar
                if showStatusBar {
                    StatusBarView(
                        stats: documentStats,
                        warningCount: lintWarnings.count,
                        percentRead: isEditMode ? nil : displayedPercentRead
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showFindBar)
        }
        .animation(.easeInOut(duration: 0.2), value: showOutlineSidebar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showOutlineSidebar.toggle()
                    }
                } label: {
                    Label("Outline", systemImage: "list.bullet.indent")
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    if !isEditMode {
                        // Entering edit mode - save current scroll position
                        savedScrollBlockIndex = currentTopBlockIndex
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditMode.toggle()
                    }
                    if isEditMode {
                        // Focus editor after animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            isEditorFocused = true
                        }
                    } else {
                        // Exiting edit mode - restore scroll position
                        if let blockIndex = savedScrollBlockIndex {
                            scrollToHeadingIndex = blockIndex
                            savedScrollBlockIndex = nil
                        }
                    }
                } label: {
                    Label(
                        isEditMode ? "Read" : "Edit",
                        systemImage: isEditMode ? "book" : "pencil"
                    )
                }
                .keyboardShortcut("e", modifiers: .command)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation {
                        isDistractionFree = true
                    }
                } label: {
                    Label("Focus", systemImage: "rectangle.expand.vertical")
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            ToolbarItem(placement: .primaryAction) {
                ShareButton(text: document.text)
            }
        }
    }

    private func updateHeadings(from text: String) {
        // For small documents, parse synchronously
        if text.count < RenderingThresholds.syncRenderMaxChars {
            let doc = MarkdownParser.parse(text)
            headings = MarkdownParser.extractHeadings(from: doc)
            rebuildHeadingLocations()
            return
        }

        // For large documents, parse on background thread
        Task {
            let extractedHeadings = await Task.detached(priority: .userInitiated) {
                let doc = MarkdownParser.parse(text)
                return MarkdownParser.extractHeadings(from: doc)
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run {
                headings = extractedHeadings
                rebuildHeadingLocations()
            }
        }
    }

    private func updateRenderedBlocks(from text: String) {
        // Cancel any in-progress render
        renderTask?.cancel()

        // Invalidate the measurement cache by swapping in fresh instances
        // rather than awaiting `clear()`. Reason: a fire-and-forget
        // `Task { await cache.clear() }` can race with the prefetch writes
        // kicked off just below (`prefetchCodeBlockMeasurements()`), wiping
        // entries that were populating for the new document. Swapping
        // instances sidesteps the race entirely — SwiftUI re-publishes the
        // new cache through `.environment(\.codeBlockMeasurementCache, …)`,
        // the old instance GCs once any in-flight writes land on it (those
        // writes are harmless and never read back).
        codeBlockMeasurementCache = CodeBlockMeasurementCache()
        tableMeasurementCache = TableMeasurementCache()

        let renderingSignposter = Signposts.signposter(for: .rendering)

        // For small documents, render synchronously to avoid flicker
        if text.count < RenderingThresholds.syncRenderMaxChars {
            DebugLog.log(.rendering, "updateRenderedBlocks: sync path (\(text.count) chars)")
            // Signpost: renderBatch index=0 — sync path is one batch covering the full doc.
            // parseMarkdown nests inside this interval (BlockRenderer.render emits it).
            let state = renderingSignposter.beginInterval(
                "renderBatch",
                id: renderingSignposter.makeSignpostID(),
                "index=0 mode=sync"
            )
            let blocks = BlockRenderer.render(text, style: renderStyle)
            renderingSignposter.endInterval("renderBatch", state, "blocks=\(blocks.count)")

            renderedBlocks = blocks
            renderedBlocksGeneration &+= 1
            rebuildHeadingLocations()
            reconfigureHeightIndex()
            prefetchCodeBlockMeasurements()
            prefetchTableMeasurements()
            emitFirstPaintIfNeeded(blockCount: blocks.count)
            return
        }

        // For large documents, use progressive rendering:
        // 1. Prepare the first structurally complete chunk off-main
        // 2. Continue rendering rest in background
        // 3. Update view incrementally
        DebugLog.log(.rendering, "updateRenderedBlocks: progressive path (\(text.count) chars)")
        isRendering = true
        let style = renderStyle  // Capture value type
        renderedBlocks = []
        renderedBlocksGeneration &+= 1
        headingLocations = []
        reconfigureHeightIndex()

        renderTask = Task {
            // The chunker performs a full swift-markdown parse to find a safe
            // boundary. Keeping both that pass and the initial render off the
            // main actor is essential for a document whose first top-level
            // block is a multi-megabyte table or code fence.
            let prepared = await Task.detached(priority: .userInitiated) {
                let firstChunkEnd = MarkdownChunker.findFirstChunkEnd(in: text)
                guard !Task.isCancelled else { return (firstChunkEnd, [MarkdownBlock]()) }

                let firstChunk = String(text.prefix(firstChunkEnd))
                let signposter = Signposts.signposter(for: .rendering)
                let initialState = signposter.beginInterval(
                    "renderBatch",
                    id: signposter.makeSignpostID(),
                    "index=0 mode=initial"
                )
                let initialBlocks = DebugLog.measure(
                    .rendering,
                    "Initial chunk (\(firstChunk.count) chars)"
                ) {
                    BlockRenderer.render(firstChunk, style: style)
                }
                signposter.endInterval("renderBatch", initialState, "blocks=\(initialBlocks.count)")
                return (firstChunkEnd, initialBlocks)
            }.value

            guard !Task.isCancelled else { return }

            let firstChunkEnd = prepared.0
            let initialBlocks = prepared.1
            renderedBlocks = initialBlocks
            renderedBlocksGeneration &+= 1
            rebuildHeadingLocations()
            reconfigureHeightIndex()
            prefetchCodeBlockMeasurements()
            prefetchTableMeasurements()
            emitFirstPaintIfNeeded(blockCount: initialBlocks.count)
            DebugLog.log(.rendering, "  → Initial \(initialBlocks.count) blocks shown")

            if firstChunkEnd >= text.count {
                isRendering = false
                DebugLog.logMemory(.perf, context: "After render complete (single chunk)")
                return
            }

            let remainingText = String(text.dropFirst(firstChunkEnd))

            // Signpost: renderBatch index=1 — background continuation. The interval spans the
            // detached parse + the main-actor append so the trace shows the full latency from
            // "background work started" to "blocks visible".
            let bgState = renderingSignposter.beginInterval(
                "renderBatch",
                id: renderingSignposter.makeSignpostID(),
                "index=1 mode=background"
            )

            let moreBlocks = await DebugLog.measureAsync(.rendering, "Background render (\(remainingText.count) chars)") {
                await Task.detached(priority: .userInitiated) {
                    // The background chunk starts mid-document, so frontmatter
                    // must never be recognized here (a leading `---` is a
                    // thematic break, not a fence).
                    BlockRenderer.render(remainingText, style: style, isDocumentStart: false)
                }.value
            }

            guard !Task.isCancelled else {
                renderingSignposter.endInterval("renderBatch", bgState, "blocks=0 cancelled=1")
                return
            }

            DebugLog.log(.rendering, "Appending \(moreBlocks.count) blocks...")
            let assignStart = CFAbsoluteTimeGetCurrent()
            renderedBlocks = initialBlocks + moreBlocks
            renderedBlocksGeneration &+= 1
            rebuildHeadingLocations()
            let assignTime = (CFAbsoluteTimeGetCurrent() - assignStart) * 1000
            DebugLog.log(.rendering, "Block append took \(String(format: "%.2f", assignTime))ms")
            DebugLog.log(.rendering, "  → Total \(renderedBlocks.count) blocks")
            isRendering = false
            reconfigureHeightIndex()
            // Prefetch measurements for the full block list — the first
            // chunk already kicked off its own; this re-runs and fast-path
            // skips cache-hits, so only the newly-appended blocks produce
            // real work.
            prefetchCodeBlockMeasurements()
            prefetchTableMeasurements()
            DebugLog.logMemory(.perf, context: "After render complete")
            renderingSignposter.endInterval("renderBatch", bgState, "blocks=\(moreBlocks.count)")
        }
    }

    /// Emit the `firstPaint` signpost event once per document-open lifecycle. Called after the
    /// first non-empty `renderedBlocks` assignment. The actual on-screen paint follows the
    /// state mutation by ~1 SwiftUI frame; this is the closest hook without coupling into
    /// LazyVStack's child lifecycle.
    private func emitFirstPaintIfNeeded(blockCount: Int) {
        guard !firstPaintFired, blockCount > 0 else { return }
        firstPaintFired = true
        Signposts.event("firstPaint", category: .rendering)
    }

    /// Dispatches off-main measurement for every large code block currently
    /// in `renderedBlocks`. Each enqueue is idempotent — cache hits
    /// short-circuit without touching the measurement queue — so calling
    /// this multiple times as the block list grows is safe.
    ///
    /// Large-block threshold matches `CodeBlockView.maxSwiftUITextChars`.
    /// Small blocks are not prefetched because they render on SwiftUI
    /// `Text`'s intrinsic-sizing path, which doesn't have the async
    /// height-shift problem this cache solves.
    ///
    /// On completion (including cache-hit fast path), each measurement is
    /// also recorded into `documentHeightIndex` at the block's index so
    /// the prefix-sum totalHeight converges to the authoritative value.
    /// The recorded height includes the view-layer chrome (padding +
    /// header) that `CodeBlockView` applies around the raw TextKit
    /// measurement, matching what `DocumentHeightIndex.defaultFallback`
    /// already accounts for in its estimate.
    private func prefetchCodeBlockMeasurements() {
        let fontFamily = resolvedCodeFontFamily
        let fontSize = CGFloat(readerFontSize * 0.875)
        let themeName = CodeBlockView.themeName(for: effectiveColorScheme)
        let cache = codeBlockMeasurementCache
        let blocks = renderedBlocks
        let heightIndex = documentHeightIndex

        for (index, block) in blocks.enumerated() {
            // Match the renderer's gate: any block whose *original* (pre-
            // segmentation) size exceeds the threshold takes the NSTextView
            // path and therefore needs its measurement warmed. Using the
            // per-slice `code.count` here would miss every segment of a
            // split block — they'd each show the placeholder on first paint
            // and do their own late measurement, re-introducing the
            // post-paint height shift this prefetch exists to prevent.
            guard case .codeBlock(let data) = block,
                  data.originalBlockSize > CodeBlockView.maxSwiftUITextChars,
                  data.originalBlockSize <= RenderingThresholds.maxHighlightedLogicalCodeBlockChars else { continue }

            let chrome = CodeBlockView.chromeHeight(
                isFirst: data.isSegmentFirst,
                isLast: data.isSegmentLast
            )

            CodeBlockMeasurementScheduler.enqueueIfNeeded(
                code: data.code,
                language: data.language,
                fontName: fontFamily ?? "",
                fontSize: fontSize,
                themeName: themeName,
                allowsHighlighting: data.originalBlockSize <= RenderingThresholds.maxHighlightedLogicalCodeBlockChars,
                cache: cache
            ) { _, result in
                // Feed the authoritative height (text + chrome) into the
                // document-wide index so totalHeight stays accurate as
                // measurements replace fallback estimates.
                heightIndex.recordHeight(result.height + chrome, at: index)
            }
        }
    }

    /// Dispatches off-main measurement for every large table currently in
    /// `renderedBlocks`. Each enqueue is idempotent — cache hits
    /// short-circuit without queueing work. Mirrors
    /// `prefetchCodeBlockMeasurements`.
    ///
    /// The virtualization threshold matches
    /// `TableBlockView.virtualizationThreshold` — below it, tables render
    /// via SwiftUI `Grid` and don't need a pre-measured column-width pass.
    private func prefetchTableMeasurements() {
        let cache = tableMeasurementCache
        let blocks = renderedBlocks

        for block in blocks {
            guard case .table(let data) = block,
                  data.rows.count >= TableBlockView.virtualizationThreshold else { continue }

            TableMeasurementScheduler.enqueueIfNeeded(
                data: data,
                bodyFontSize: 14,
                headerFontSize: 14,
                cache: cache
            ) { _, _ in
                // Intentionally empty — TableBlockView reads the cache via
                // environment on `.onAppear` and swaps from placeholder to
                // measured layout. No document-height feedback needed: the
                // placeholder is already at the authoritative total height.
            }
        }
    }

    /// Reset the document height index for the current block list. Called
    /// on every `renderedBlocks` assignment. The fallback closure captures
    /// the current block array and code-font line metrics; re-running this
    /// for a superset of blocks invalidates prior measurements — which is
    /// fine because the cache still holds them and the prefetch re-fires
    /// and re-records (cheap: cache hits, no TextKit work).
    private func reconfigureHeightIndex() {
        let codeFont = CodeBlockView.nsFont(
            family: resolvedCodeFontFamily,
            size: CGFloat(readerFontSize * 0.875)
        )
        // Snapshot blocks so the spacing closure doesn't re-read the
        // @State array on every invocation (the index queries once per
        // block during rebuild).
        let snapshot = renderedBlocks
        documentHeightIndex.configure(
            blockCount: snapshot.count,
            blockSpacing: 16,
            fallback: DocumentHeightIndex.defaultFallback(
                for: snapshot,
                codeFont: codeFont
            ),
            spacingProvider: { index in
                BlockSpacing.topSpacing(at: index, in: snapshot)
            }
        )
    }

    private func scrollToHeading(_ heading: HeadingInfo) {
        selectedHeadingID = heading.id
        scrollToHeadingIndex = headingLocations.first(where: { $0.heading.id == heading.id })?.blockIndex
    }

    /// Build the heading lookup once when either input changes. Matching is a
    /// linear pass over blocks followed by a linear pass over headings;
    /// scrolling then needs only a binary search.
    private func rebuildHeadingLocations() {
        guard !headings.isEmpty, !renderedBlocks.isEmpty else {
            headingLocations = []
            return
        }

        var blockIndicesByText: [String: [Int]] = [:]
        for (index, block) in renderedBlocks.enumerated() {
            guard case .text(let attributed) = block else { continue }
            let text = String(attributed.characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            blockIndicesByText[text, default: []].append(index)
        }

        var consumedByText: [String: Int] = [:]
        var locations: [(heading: HeadingInfo, blockIndex: Int)] = []
        locations.reserveCapacity(headings.count)
        for heading in headings {
            let text = heading.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let consumed = consumedByText[text, default: 0]
            guard let candidates = blockIndicesByText[text], consumed < candidates.count else { continue }
            locations.append((heading, candidates[consumed]))
            consumedByText[text] = consumed + 1
        }
        headingLocations = locations.sorted { $0.blockIndex < $1.blockIndex }
    }

    /// Finds the heading that corresponds to (or precedes) the given block index.
    private func headingForBlock(_ blockIndex: Int) -> HeadingInfo? {
        var lower = 0
        var upper = headingLocations.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if headingLocations[middle].blockIndex <= blockIndex {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower > 0 ? headingLocations[lower - 1].heading : nil
    }

    private func updateCurrentHeading(forBlockIndex blockIndex: Int) {
        currentTopBlockIndex = blockIndex
        if let heading = headingForBlock(blockIndex) {
            // Only update if different to avoid unnecessary state changes
            if selectedHeadingID != heading.id {
                selectedHeadingID = heading.id
            }
        }
    }

    // MARK: - Find Bar

    private func showFind() {
        withAnimation(.easeInOut(duration: 0.15)) {
            showFindBar = true
        }
    }

    private func dismissFindBar() {
        withAnimation(.easeInOut(duration: 0.15)) {
            showFindBar = false
            showReplace = false
            searchText = ""
            replaceText = ""
            searchMatches = []
            matchTexts = []
            currentMatchIndex = 0
        }
    }

    /// The text of the current match (for replacement preview).
    /// Reads from the `matchTexts` cache populated by `updateSearch` — avoids
    /// re-running `TextSearcher.findMatches` on every SwiftUI re-render.
    private var currentMatchText: String? {
        guard currentMatchIndex < matchTexts.count else { return nil }
        return matchTexts[currentMatchIndex]
    }

    private func showFindAndReplace() {
        withAnimation(.easeInOut(duration: 0.15)) {
            showFindBar = true
            showReplace = true
        }
    }

    private func updateSearch() {
        guard !searchText.isEmpty else {
            searchMatches = []
            matchTexts = []
            currentMatchIndex = 0
            searchResultGeneration &+= 1
            return
        }
        // Count matches in rendered blocks (same as highlighting uses)
        let (matches, texts) = countMatchesInRenderedBlocks()
        searchMatches = matches
        matchTexts = texts
        currentMatchIndex = 0
        searchResultGeneration &+= 1
    }

    /// Counts matches in the rendered block text (not raw markdown) and
    /// captures the matched substring for each. Returning the texts alongside
    /// the matches lets `currentMatchText` skip a full-document re-search on
    /// every SwiftUI re-render.
    private func countMatchesInRenderedBlocks() -> (matches: [TextSearcher.Match], texts: [String]) {
        var allMatches: [TextSearcher.Match] = []
        var allTexts: [String] = []

        for block in renderedBlocks {
            if case .text(let attrString) = block {
                let blockText = String(attrString.characters)
                let matches = TextSearcher.findMatches(
                    query: searchText,
                    in: blockText,
                    caseSensitive: caseSensitive,
                    useRegex: useRegex
                )
                for match in matches {
                    allMatches.append(match)
                    allTexts.append(String(blockText[match.range]))
                }
            }
        }

        return (allMatches, allTexts)
    }

    private func findNext() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % searchMatches.count
    }

    private func findPrevious() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = currentMatchIndex == 0 ? searchMatches.count - 1 : currentMatchIndex - 1
    }

    /// The raw-document matches a replace is allowed to touch: the ones outside
    /// code fences, mirroring the prose universe the counter and highlights use.
    /// When this set doesn't line up one-for-one with the displayed matches
    /// (`searchMatches`), the two universes have diverged — a match in a table,
    /// math block, or frontmatter — and we refuse rather than edit an occurrence
    /// the user never saw highlighted.
    private func replaceableMatches() -> [TextSearcher.Match]? {
        let matches = TextSearcher.matchesOutsideFences(
            query: searchText,
            in: document.text,
            caseSensitive: caseSensitive,
            useRegex: useRegex
        )
        guard matches.count == searchMatches.count else {
            // Divergent universes — do not guess which occurrence to edit.
            DebugLog.log(.rendering, "Replace refused: \(matches.count) editable vs \(searchMatches.count) displayed matches")
            NSSound.beep()
            return nil
        }
        return matches
    }

    private func replaceCurrent() {
        guard !searchText.isEmpty, !searchMatches.isEmpty else { return }
        guard let matches = replaceableMatches(), currentMatchIndex < matches.count else { return }

        var newText = document.text
        newText.replaceSubrange(matches[currentMatchIndex].range, with: replaceText)
        document.text = newText

        // Update search results
        updateSearch()

        // Adjust current match index if needed
        if currentMatchIndex >= searchMatches.count && !searchMatches.isEmpty {
            currentMatchIndex = searchMatches.count - 1
        }
    }

    private func replaceAll() {
        guard !searchText.isEmpty, !searchMatches.isEmpty else { return }
        guard let matches = replaceableMatches() else { return }

        // Replace all occurrences (work backwards to preserve indices)
        var newText = document.text
        for match in matches.reversed() {
            newText.replaceSubrange(match.range, with: replaceText)
        }

        document.text = newText
        updateSearch()
        currentMatchIndex = 0
    }

    private func scrollToMatch(_ matchIndex: Int, proxy: ScrollViewProxy) {
        if let blockIdx = MarkdownReaderViewWithAnchors.blockIndexForMatch(
            matchIndex,
            searchText: searchText,
            caseSensitive: caseSensitive,
            useRegex: useRegex,
            in: renderedBlocks
        ) {
            if renderedBlocks.count > 1000 {
                largeDocumentNavigator.scroll(to: blockIdx, anchor: .center)
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo("block-\(blockIdx)", anchor: .center)
                }
            }
        }
    }

    private func setupDebouncing() {
        // Guard against duplicate subscriptions
        guard cancellables.isEmpty else { return }

        // Debounce expensive operations (150ms) - parsing, rendering, outline
        textUpdatePublisher
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [self] newText in
                debouncedText = newText
                updateHeadings(from: newText)
                updateRenderedBlocks(from: newText)
            }
            .store(in: &cancellables)

        // Lint debouncing (500ms to avoid excessive linting while typing)
        lintUpdatePublisher
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [self] text in
                updateLintWarnings(for: text)
            }
            .store(in: &cancellables)

        // Search debouncing (100ms to avoid excessive match counting)
        searchUpdatePublisher
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [self] in
                updateSearch()
            }
            .store(in: &cancellables)
    }

    // MARK: - File Watching

    private func setupFileWatcher() {
        guard let url = fileURL else { return }

        // Store initial modification date
        lastKnownModDate = url.fileModificationDate

        // Set up watcher for external changes
        fileWatcher = FileWatcher(url: url) { [self] in
            let resolution = ExternalChangeDetector.resolve(
                currentModDate: url.fileModificationDate,
                lastKnownModDate: lastKnownModDate,
                isOwnSaveInProgress: suppressExternalChangeAlert
            )

            switch resolution {
            case .ownSaveInProgress:
                lastKnownModDate = url.fileModificationDate
            case .externalChange:
                // mtime changed — but confirm the on-disk CONTENT actually
                // differs from our buffer before prompting. Our own writes (a
                // task-checkbox toggle, format-on-save, an autosave) bump the
                // mtime without diverging from what we already have, so a plain
                // mtime check nagged "reload?" on every self-save. Only a genuine
                // external edit (different content) should prompt — sparing by
                // construction.
                if let data = try? Data(contentsOf: url),
                   let diskText = String(data: data, encoding: .utf8),
                   diskText == document.text {
                    lastKnownModDate = url.fileModificationDate
                } else {
                    DispatchQueue.main.async {
                        showExternalChangeAlert = true
                    }
                }
            case .noChange:
                break
            }
        }
    }

    private func reloadFromDisk() {
        guard let url = fileURL else { return }

        // Signpost is placed after the early-return guard so a 0-duration "no fileURL" case
        // doesn't pollute the trace — only real reload work shows up on the timeline.
        let signposter = Signposts.signposter(for: .lifecycle)
        let state = signposter.beginInterval("reloadFromDisk")
        defer { signposter.endInterval("reloadFromDisk", state) }

        // Reset firstPaint guard so the post-reload render emits a fresh `firstPaint` event,
        // paired with this `reloadFromDisk` interval per design.md.
        firstPaintFired = false

        // Prefer NSDocument.revert so the reload does not mark the document dirty.
        // SwiftUI's DocumentGroup owns an NSDocument under the hood; revert re-reads
        // the file through the normal FileDocument.init(configuration:) path and
        // clears the change count.
        if let nsDoc = NSDocumentController.shared.document(for: url) {
            do {
                let type = nsDoc.fileType ?? "public.plain-text"
                try nsDoc.revert(toContentsOf: url, ofType: type)
                lastKnownModDate = url.fileModificationDate
                // onChange(of: document.text) handles re-rendering.
                return
            } catch {
                DebugLog.error(.lifecycle, "NSDocument revert failed: \(error.localizedDescription) — falling back to direct read")
            }
        }

        // Fallback: direct read (will mark document dirty, but better than no reload).
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        document.text = text
        lastKnownModDate = url.fileModificationDate
        updateHeadings(from: text)
        updateRenderedBlocks(from: text)
    }

    /// Checks for save conflicts before saving. Returns true if safe to save.
    func checkSaveConflict() -> Bool {
        SaveConflictPolicy.isSafeToSave(
            currentModDate: fileURL?.fileModificationDate,
            lastKnownModDate: lastKnownModDate
        )
    }

    private var readerView: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView {
                    VStack(spacing: 0) {
                        // Read the actual NSScrollView geometry. Keep the
                        // representable inside the document's root stack so
                        // its AppKit ancestry is the same reliable path used
                        // by ScrollAutoDriver.
                        ScrollPercentageObserver(onPositionChange: handleScrollPosition)
                            .frame(width: 0, height: 0)

                        // Anchor at top for scroll restoration
                        Color.clear.frame(height: 1).id("top")

                        #if DEBUG
                        // Debug-only: programmatic autoscroll driver for
                        // profile runs. No-ops unless VOID_READER_AUTOSCROLL=1.
                        ScrollAutoDriver()
                            .frame(width: 0, height: 0)
                        #endif

                        MarkdownReaderViewWithAnchors(
                            text: document.text,
                            headings: headings,
                            blocks: renderedBlocks,
                            contentGeneration: renderedBlocksGeneration,
                            documentURL: fileURL,
                            searchText: searchText,
                            caseSensitive: caseSensitive,
                            useRegex: useRegex,
                            currentMatchIndex: currentMatchIndex,
                            codeFontSize: CGFloat(readerFontSize * 0.875),
                            codeFontFamily: resolvedCodeFontFamily,
                            onTaskToggle: handleTaskToggle,
                            onTopBlockChange: updateCurrentHeading,
                            onMermaidExpand: handleMermaidExpand,
                            largeDocumentNavigator: largeDocumentNavigator
                        )
                        .environment(\.codeBlockMeasurementCache, codeBlockMeasurementCache)
                        .environment(\.tableMeasurementCache, tableMeasurementCache)
                        .environment(\.documentHeightIndex, documentHeightIndex)
                        .environment(\.onImageExpand, handleImageExpand)
                        .environment(\.openURL, OpenURLAction { url in
                            return handleLinkClick(url)
                        })
                        .padding(fullWidthReader ? 24 : 40)
                        .frame(maxWidth: fullWidthReader ? .infinity : 720, alignment: .leading)
                    }
                }
                .coordinateSpace(name: "reader-scroll")

                // Loading indicator for large documents
                if isRendering {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Rendering document...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onAppear {
                scrollProxy = proxy
                // Small/sync documents never toggle isRendering, so also try to
                // restore here; the hasRestoredScroll guard keeps it to once.
                restoreScrollPosition(proxy: proxy)
            }
            .onDisappear {
                saveScrollPosition()
            }
            .onChange(of: isRendering) { _, newValue in
                // Restore scroll position after progressive rendering completes.
                if !newValue && !renderedBlocks.isEmpty {
                    restoreScrollPosition(proxy: proxy)
                }
            }
            .onChange(of: scrollToHeadingIndex) { _, newIndex in
                // Don't scroll while rendering
                guard !isRendering, let index = newIndex else { return }
                if renderedBlocks.count > 1000 {
                    largeDocumentNavigator.scroll(to: index, anchor: .top)
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("block-\(index)", anchor: .top)
                    }
                }
                // Reset after scrolling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    scrollToHeadingIndex = nil
                }
            }
            .onChange(of: currentMatchIndex) { _, newIndex in
                guard !isRendering else { return }
                scrollToMatch(newIndex, proxy: proxy)
            }
            .onChange(of: searchResultGeneration) { _, _ in
                // A different query may have the same match count and leave
                // currentMatchIndex at zero. Generation is the authoritative
                // signal that the first-result destination changed.
                guard !isRendering, !searchMatches.isEmpty else { return }
                scrollToMatch(0, proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityIdentifier("reader-view")
    }

    private func saveScrollPosition() {
        guard let path = fileURL?.path else { return }
        ScrollPositionStore.shared.savePosition(scrollFractionForPersistence, for: path)
    }

    private func restoreScrollPosition(proxy: ScrollViewProxy) {
        guard !hasRestoredScroll,
              let path = fileURL?.path,
              let savedFraction = ScrollPositionStore.shared.position(for: path),
              savedFraction > 0.01 else { return }

        // Block heights are measured asynchronously, so DocumentHeightIndex may
        // not be populated the instant the view appears. Poll a few times, then
        // map the saved fraction to the nearest block and scroll to its anchor
        // (the reader tags each row `.id("block-<index>")`).
        func attempt(_ remaining: Int) {
            // Don't yank the user if they've already scrolled away from the top.
            guard scrollOffsetForPercent < 50 else { hasRestoredScroll = true; return }

            let total = documentHeightIndex.totalHeight
            guard total > 0 else {
                if remaining > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { attempt(remaining - 1) }
                }
                return
            }
            hasRestoredScroll = true
            let targetOffset = total * CGFloat(savedFraction)
            let blockIdx = documentHeightIndex.blockIndex(atOffset: targetOffset)
            if renderedBlocks.count > 1000 {
                largeDocumentNavigator.scroll(to: blockIdx, anchor: .top)
            } else {
                proxy.scrollTo("block-\(blockIdx)", anchor: .top)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { attempt(6) }
    }

    private func handleTaskToggle(id: UUID, newState: Bool) {
        // Map the tapped item's stable id to its ordinal among all rendered task
        // slots (document order), then toggle that slot by source line. Walking
        // renderedBlocks — the exact list the reader shows — keeps the ordinal in
        // step with what the user clicked, across multiple task lists and mixed
        // markers, instead of the old block-local index that addressed the wrong
        // line whenever those diverged.
        var ordinal = 0
        for block in renderedBlocks {
            guard case .taskList(let items) = block else { continue }
            for item in items {
                if item.id == id {
                    document.text = MarkdownTextUtils.toggleTask(
                        in: document.text,
                        taskOrdinal: ordinal,
                        expectedChecked: item.isChecked,
                        to: newState
                    )
                    return
                }
                ordinal += 1
            }
        }
    }

    private func handleScrollPosition(_ position: ReaderScrollPosition) {
        scrollOffsetForPercent = position.offset
        scrollFractionForPersistence = position.fraction

        guard !isEditMode, position.percent != displayedPercentRead else { return }
        displayedPercentRead = position.percent
    }

    private func handleMermaidExpand(_ source: String) {
        expandedMermaidSource = source
    }

    private func handleImageExpand(_ imageData: ExpandedImageData) {
        expandedImageData = imageData
    }

    // MARK: - Link Handling

    private func handleLinkClick(_ url: URL) -> OpenURLAction.Result {
        // In-document anchor links (void-anchor:slug)
        if url.scheme == "void-anchor" {
            let targetSlug = url.absoluteString
                .replacingOccurrences(of: "void-anchor:", with: "")
                .removingPercentEncoding ?? ""
            if let heading = headings.first(where: { $0.slug == targetSlug }) {
                scrollToHeading(heading)
            }
            return .handled
        }

        // Relative file links (void-file:path) — resolve against current document
        if url.scheme == "void-file" {
            guard let docURL = fileURL else { return .discarded }
            let relativePath = url.absoluteString
                .replacingOccurrences(of: "void-file:", with: "")
                .removingPercentEncoding ?? ""
            let baseDir = docURL.deletingLastPathComponent()
            let resolvedURL = baseDir.appendingPathComponent(relativePath).standardized

            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                NSDocumentController.shared.openDocument(
                    withContentsOf: resolvedURL,
                    display: true
                ) { _, _, error in
                    if let error = error {
                        DebugLog.error(.lifecycle, "Failed to open linked file: \(error.localizedDescription)")
                    }
                }
                return .handled
            }
            return .discarded
        }

        // Everything else: let the system handle it (opens in browser, etc.)
        return .systemAction
    }

    // MARK: - Formatting

    private func formatDocument() {
        let options = FormatterOptions(
            listMarker: FormatterOptions.ListMarkerStyle(rawValue: listMarkerStyle) ?? .dash,
            emphasisMarker: FormatterOptions.EmphasisMarkerStyle(rawValue: emphasisMarkerStyle) ?? .star
        )

        let formatted = MarkdownFormatter.format(document.text, options: options)
        if formatted != document.text {
            // Suppress file watcher alert for our own save
            suppressExternalChangeAlert = true
            document.text = formatted

            // Clear suppression and update mod date after save completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                suppressExternalChangeAlert = false
                lastKnownModDate = fileURL?.fileModificationDate
            }
        }
    }

    // MARK: - Linting

    private func updateLintWarnings(for text: String) {
        // Build set of enabled rules (all rules minus disabled ones)
        let disabled = Set(disabledLintRules.split(separator: ",").map(String.init))
        let enabled = MarkdownLinter.allRuleIDs.subtracting(disabled)

        lintWarnings = MarkdownLinter.lint(text, enabledRules: enabled)
    }

    private var editorView: some View {
        ResizableSplitView(
            leftFraction: Binding(
                get: { CGFloat(editorSplitFraction) },
                set: { editorSplitFraction = Double($0) }
            )
        ) {
            // Source editor with syntax highlighting
            SyntaxHighlightingEditor(
                text: $document.text,
                theme: currentTheme,
                colorScheme: effectiveColorScheme,
                font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                lintWarnings: lintWarnings
            )
        } right: {
            // Preview (uses debounced text and cached blocks for performance)
            ScrollViewReader { proxy in
                ScrollView {
                    MarkdownReaderViewWithAnchors(
                        text: debouncedText,
                        headings: headings,
                        blocks: renderedBlocks,
                        contentGeneration: renderedBlocksGeneration,
                        documentURL: fileURL,
                        codeFontSize: CGFloat(readerFontSize * 0.875),
                        codeFontFamily: resolvedCodeFontFamily,
                        onTaskToggle: handleTaskToggle,
                        onMermaidExpand: handleMermaidExpand,
                        largeDocumentNavigator: largeDocumentNavigator
                    )
                    .environment(\.codeBlockMeasurementCache, codeBlockMeasurementCache)
                    .environment(\.tableMeasurementCache, tableMeasurementCache)
                    .environment(\.documentHeightIndex, documentHeightIndex)
                    .environment(\.onImageExpand, handleImageExpand)
                    .environment(\.openURL, OpenURLAction { url in
                        return handleLinkClick(url)
                    })
                    .padding(fullWidthReader ? 24 : 40)
                    .frame(maxWidth: fullWidthReader ? .infinity : 720, alignment: .leading)
                }
                .onChange(of: scrollToHeadingIndex) { _, newIndex in
                    if let index = newIndex {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("block-\(index)", anchor: .top)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            scrollToHeadingIndex = nil
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

/// Preference key for tracking scroll position in reader view
private struct ReaderScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    ContentView(document: .constant(MarkdownDocument(text: """
    # Hello VoidReader

    This is a **markdown** preview.

    - Item one
    - Item two
    - Item three

    ```swift
    let greeting = "Hello, World!"
    ```
    """)))
}
