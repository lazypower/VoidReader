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

    // Debounce publisher for preview updates
    @State private var textUpdatePublisher = PassthroughSubject<String, Never>()
    @State private var cancellables = Set<AnyCancellable>()

    // For print/export/share/format commands
    private let printPublisher = NotificationCenter.default.publisher(for: .printDocument)
    private let exportPDFPublisher = NotificationCenter.default.publisher(for: .exportPDF)
    private let sharePublisher = NotificationCenter.default.publisher(for: .shareDocument)
    private let formatDocumentPublisher = NotificationCenter.default.publisher(for: .formatDocument)
    private let reloadFromDiskPublisher = NotificationCenter.default.publisher(for: .reloadFromDisk)

    // Share sheet state
    @State private var showingShare = false

    // Scroll position tracking
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?
    @State private var savedScrollBlockIndex: Int?
    @State private var currentTopBlockIndex: Int = 0
    @State private var displayedPercentRead: Int = 0
    @State private var scrollOffsetForPercent: CGFloat = 0
    @State private var percentUpdateTask: Task<Void, Never>?

    // Find bar
    @State private var showFindBar = false
    @State private var showReplace = false
    @State private var searchText = ""
    @State private var replaceText = ""
    @State private var caseSensitive = false
    @State private var useRegex = false
    @State private var searchMatches: [TextSearcher.Match] = []
    @State private var currentMatchIndex = 0

    // Cached rendered blocks (expensive to compute)
    @State private var renderedBlocks: [MarkdownBlock] = []
    @State private var isRendering = false
    @State private var renderTask: Task<Void, Never>?
    /// Guard for the `firstPaint` signpost event so it fires exactly once per
    /// document-open lifecycle. Reset to false in `reloadFromDisk()` so the next paint
    /// after a reload re-fires it (paired with the `reloadFromDisk` interval).
    @State private var firstPaintFired = false

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
            // DIAGNOSTIC: confirm whether signposts are enabled at runtime. Remove after debugging.
            DebugLog.info(.lifecycle, "Signposts.lifecycle.isEnabled=\(Signposts.lifecycle.isEnabled) rendering.isEnabled=\(Signposts.rendering.isEnabled)")
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
        guard let window = NSApplication.shared.keyWindow else { return }
        DocumentPrinter.print(text: document.text, documentURL: fileURL, from: window)
    }

    private func exportPDF() {
        guard let window = NSApplication.shared.keyWindow else { return }
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
        if text.count < 50_000 {
            let doc = MarkdownParser.parse(text)
            headings = MarkdownParser.extractHeadings(from: doc)
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
            }
        }
    }

    private func updateRenderedBlocks(from text: String) {
        // Cancel any in-progress render
        renderTask?.cancel()

        let renderingSignposter = Signposts.signposter(for: .rendering)

        // For small documents, render synchronously to avoid flicker
        if text.count < 50_000 {
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
            emitFirstPaintIfNeeded(blockCount: blocks.count)
            return
        }

        // For large documents, use progressive rendering:
        // 1. Render first screen immediately (fast)
        // 2. Continue rendering rest in background
        // 3. Update view incrementally
        DebugLog.log(.rendering, "updateRenderedBlocks: progressive path (\(text.count) chars)")
        isRendering = true
        let style = renderStyle  // Capture value type

        // Step 1: Immediately render the first chunk (first ~20KB or first 500 lines)
        let firstChunkEnd = findFirstChunkEnd(in: text)
        let firstChunk = String(text.prefix(firstChunkEnd))

        // Signpost: renderBatch index=0 — initial progressive chunk.
        let initialState = renderingSignposter.beginInterval(
            "renderBatch",
            id: renderingSignposter.makeSignpostID(),
            "index=0 mode=initial"
        )
        let initialBlocks = DebugLog.measure(.rendering, "Initial chunk (\(firstChunk.count) chars)") {
            BlockRenderer.render(firstChunk, style: style)
        }
        renderingSignposter.endInterval("renderBatch", initialState, "blocks=\(initialBlocks.count)")

        renderedBlocks = initialBlocks
        emitFirstPaintIfNeeded(blockCount: initialBlocks.count)
        DebugLog.log(.rendering, "  → Initial \(initialBlocks.count) blocks shown immediately")

        // If we rendered everything in the first chunk, we're done
        if firstChunkEnd >= text.count {
            isRendering = false
            DebugLog.logMemory(.perf, context: "After render complete (single chunk)")
            return
        }

        // Step 2: Render the rest in background
        let remainingText = String(text.dropFirst(firstChunkEnd))

        renderTask = Task {
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
                    BlockRenderer.render(remainingText, style: style)
                }.value
            }

            guard !Task.isCancelled else {
                renderingSignposter.endInterval("renderBatch", bgState, "blocks=0 cancelled=1")
                return
            }

            await MainActor.run {
                DebugLog.log(.rendering, "Appending \(moreBlocks.count) blocks...")
                let assignStart = CFAbsoluteTimeGetCurrent()
                renderedBlocks = initialBlocks + moreBlocks
                let assignTime = (CFAbsoluteTimeGetCurrent() - assignStart) * 1000
                DebugLog.log(.rendering, "Block append took \(String(format: "%.2f", assignTime))ms")
                DebugLog.log(.rendering, "  → Total \(renderedBlocks.count) blocks")
                isRendering = false
                DebugLog.logMemory(.perf, context: "After render complete")
                renderingSignposter.endInterval("renderBatch", bgState, "blocks=\(moreBlocks.count)")
            }
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

    /// Find the end of the first chunk - targets ~20KB or ~500 lines, whichever comes first.
    /// Always ends at a line boundary to avoid breaking markdown elements.
    private func findFirstChunkEnd(in text: String) -> Int {
        let targetSize = 20_000  // ~20KB
        let maxLines = 500

        var lineCount = 0
        var charCount = 0

        for char in text {
            charCount += 1
            if char == "\n" {
                lineCount += 1
                // Stop if we hit either limit
                if charCount >= targetSize || lineCount >= maxLines {
                    return charCount
                }
            }
        }

        return text.count  // Document is smaller than our target
    }

    private func scrollToHeading(_ heading: HeadingInfo) {
        selectedHeadingID = heading.id
        // Find which block contains this heading and scroll there
        if let blockIdx = MarkdownReaderViewWithAnchors.blockIndex(for: heading.text, in: renderedBlocks) {
            scrollToHeadingIndex = blockIdx
        }
    }

    /// Finds the heading that corresponds to (or precedes) the given block index.
    private func headingForBlock(_ blockIndex: Int) -> HeadingInfo? {
        // Build mapping of heading -> block index
        var headingBlocks: [(heading: HeadingInfo, blockIndex: Int)] = []
        for heading in headings {
            if let idx = MarkdownReaderViewWithAnchors.blockIndex(for: heading.text, in: renderedBlocks) {
                headingBlocks.append((heading, idx))
            }
        }

        // Find the last heading whose block is <= the current block
        let preceding = headingBlocks.filter { $0.blockIndex <= blockIndex }
        return preceding.last?.heading
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
            currentMatchIndex = 0
        }
    }

    /// The text of the current match (for replacement preview).
    private var currentMatchText: String? {
        guard !searchMatches.isEmpty, currentMatchIndex < searchMatches.count else { return nil }
        let matches = TextSearcher.findMatches(
            query: searchText,
            in: document.text,
            caseSensitive: caseSensitive,
            useRegex: useRegex
        )
        guard currentMatchIndex < matches.count else { return nil }
        let match = matches[currentMatchIndex]
        return String(document.text[match.range])
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
            currentMatchIndex = 0
            return
        }
        // Count matches in rendered blocks (same as highlighting uses)
        searchMatches = countMatchesInRenderedBlocks()
        currentMatchIndex = searchMatches.isEmpty ? 0 : 0
    }

    /// Counts matches in the rendered block text (not raw markdown).
    private func countMatchesInRenderedBlocks() -> [TextSearcher.Match] {
        var allMatches: [TextSearcher.Match] = []

        for block in renderedBlocks {
            if case .text(let attrString) = block {
                let blockText = String(attrString.characters)
                let matches = TextSearcher.findMatches(
                    query: searchText,
                    in: blockText,
                    caseSensitive: caseSensitive,
                    useRegex: useRegex
                )
                allMatches.append(contentsOf: matches)
            }
        }

        return allMatches
    }

    private func findNext() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % searchMatches.count
    }

    private func findPrevious() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = currentMatchIndex == 0 ? searchMatches.count - 1 : currentMatchIndex - 1
    }

    private func replaceCurrent() {
        guard !searchText.isEmpty, !searchMatches.isEmpty else { return }

        // Replace the current match in the document text
        // We need to find the actual position in the raw text
        let matches = TextSearcher.findMatches(
            query: searchText,
            in: document.text,
            caseSensitive: caseSensitive,
            useRegex: useRegex
        )
        guard currentMatchIndex < matches.count else { return }

        let match = matches[currentMatchIndex]
        var newText = document.text
        newText.replaceSubrange(match.range, with: replaceText)
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

        // Replace all occurrences (work backwards to preserve indices)
        let matches = TextSearcher.findMatches(
            query: searchText,
            in: document.text,
            caseSensitive: caseSensitive,
            useRegex: useRegex
        )
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
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo("block-\(blockIdx)", anchor: .center)
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
                DispatchQueue.main.async {
                    showExternalChangeAlert = true
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
                    // Scroll position tracker - MUST be outside LazyVStack to fire continuously
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .named("reader-scroll")).minY) { _, newY in
                                updateScrollPercent(offset: -newY)
                            }
                            .onAppear {
                                updateScrollPercent(offset: -geo.frame(in: .named("reader-scroll")).minY)
                            }
                    }
                    .frame(height: 0)

                    VStack(spacing: 0) {
                        // Anchor at top for scroll restoration
                        Color.clear.frame(height: 1).id("top")

                        MarkdownReaderViewWithAnchors(
                            text: document.text,
                            headings: headings,
                            blocks: renderedBlocks,
                            documentURL: fileURL,
                            searchText: searchText,
                            caseSensitive: caseSensitive,
                            useRegex: useRegex,
                            currentMatchIndex: currentMatchIndex,
                            codeFontSize: CGFloat(readerFontSize * 0.875),
                            codeFontFamily: resolvedCodeFontFamily,
                            onTaskToggle: handleTaskToggle,
                            onTopBlockChange: updateCurrentHeading,
                            onScrollProgress: handleScrollProgress,
                            onMermaidExpand: handleMermaidExpand
                        )
                        .environment(\.onImageExpand, handleImageExpand)
                        .environment(\.openURL, OpenURLAction { url in
                            return handleLinkClick(url)
                        })
                        .padding(fullWidthReader ? 24 : 40)
                        .frame(maxWidth: fullWidthReader ? .infinity : 720, alignment: .leading)
                    }
                    .background(
                        GeometryReader { contentGeo in
                            Color.clear
                                .onChange(of: contentGeo.size.height) { _, newHeight in
                                    contentHeight = newHeight
                                    updateScrollPercent(offset: scrollOffsetForPercent)
                                }
                                .onAppear {
                                    contentHeight = contentGeo.size.height
                                }
                        }
                    )
                }
                .coordinateSpace(name: "reader-scroll")
                .overlay(
                    GeometryReader { scrollGeo in
                        Color.clear
                            .onAppear {
                                visibleHeight = scrollGeo.size.height
                            }
                            .onChange(of: scrollGeo.size.height) { _, newHeight in
                                visibleHeight = newHeight
                                updateScrollPercent(offset: scrollOffsetForPercent)
                            }
                    }
                )

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
            }
            .onDisappear {
                saveScrollPosition()
            }
            .onChange(of: isRendering) { _, newValue in
                // Restore scroll position after rendering completes
                if !newValue && !renderedBlocks.isEmpty {
                    restoreScrollPosition(proxy: proxy)
                }
            }
            .onChange(of: scrollToHeadingIndex) { _, newIndex in
                // Don't scroll while rendering
                guard !isRendering, let index = newIndex else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("block-\(index)", anchor: .top)
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
            .onChange(of: searchMatches.count) { _, _ in
                // Scroll to first match when search results change
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
        // Save normalized position (0-1)
        let normalized = contentHeight > 0 ? scrollOffset / contentHeight : 0
        ScrollPositionStore.shared.savePosition(normalized, for: path)
    }

    private func restoreScrollPosition(proxy: ScrollViewProxy) {
        guard let path = fileURL?.path,
              let savedPosition = ScrollPositionStore.shared.position(for: path) else { return }

        // Delay to allow content to render
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // For now, just scroll to top - proper restoration would need custom scroll view
            // This is a simplified implementation
            if savedPosition > 0.1 {
                // We can't easily scroll to a pixel offset in SwiftUI
                // A more complete implementation would use NSScrollView directly
            }
        }
    }

    private func handleTaskToggle(index: Int, newState: Bool) {
        document.text = MarkdownTextUtils.toggleTask(in: document.text, at: index, to: newState)
    }

    private func handleScrollProgress(_ percent: Int) {
        DebugLog.log(.scroll, "ContentView.handleScrollProgress: \(percent)%, current displayedPercentRead=\(displayedPercentRead)")
        // Debounce to update on scroll stop
        percentUpdateTask?.cancel()
        percentUpdateTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            DebugLog.log(.scroll, "  → setting displayedPercentRead=\(percent)")
            displayedPercentRead = percent
        }
    }

    /// Update scroll percentage based on scroll offset
    private func updateScrollPercent(offset: CGFloat) {
        // Store offset for later recalculation when dimensions change
        scrollOffsetForPercent = offset

        // Skip if in edit mode
        guard !isEditMode else { return }

        let percent = ScrollPercentage.calculate(
            offset: offset,
            contentHeight: contentHeight,
            visibleHeight: visibleHeight
        )

        // Only update if changed
        if percent != displayedPercentRead {
            displayedPercentRead = percent
        }
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
                        documentURL: fileURL,
                        codeFontSize: CGFloat(readerFontSize * 0.875),
                        codeFontFamily: resolvedCodeFontFamily,
                        onTaskToggle: handleTaskToggle,
                        onMermaidExpand: handleMermaidExpand
                    )
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
