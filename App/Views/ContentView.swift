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

    // Share sheet state
    @State private var showingShare = false

    // Scroll position tracking
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?
    @State private var savedScrollBlockIndex: Int?
    @State private var currentTopBlockIndex: Int = 0
    @State private var displayedPercentRead: Int = 0
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

    // Lint warnings
    @State private var lintWarnings: [LintWarning] = []
    @State private var lintUpdatePublisher = PassthroughSubject<String, Never>()

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
        .cheatSheetOnHold(isShowing: $showCheatSheet)
        .onAppear {
            setupDebouncing()
        }
        .onChange(of: document.text) { _, newValue in
            // Send to debounce publisher for expensive operations
            textUpdatePublisher.send(newValue)
            // Update stats immediately (cheap operation)
            documentStats = DocumentStats(text: newValue)
            // Send to lint debouncer (500ms)
            lintUpdatePublisher.send(newValue)
        }
        .onAppear {
            updateHeadings(from: document.text)
            updateRenderedBlocks(from: document.text)
            setupFileWatcher()
        }
        .onDisappear {
            fileWatcher?.stop()
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
        .onChange(of: searchText) { _, _ in
            updateSearch()
        }
        .onChange(of: caseSensitive) { _, _ in
            updateSearch()
        }
        .onChange(of: useRegex) { _, _ in
            updateSearch()
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
        DocumentPrinter.print(text: document.text, from: window)
    }

    private func exportPDF() {
        guard let window = NSApplication.shared.keyWindow else { return }
        // Use document title or fallback
        let suggestedName = "Document.pdf"
        DocumentPrinter.exportPDF(text: document.text, suggestedName: suggestedName, from: window)
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

        // Apply theme colors for non-System themes
        if !currentTheme.isSystemTheme {
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
        // For System theme, leave colors as nil to use semantic macOS colors

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
        "\(readerFontFamily)-\(readerFontSize)-\(codeFontFamily)-\(selectedThemeID)-\(systemColorScheme)-\(appearanceOverride)"
    }

    private func increaseFontSize() {
        readerFontSize = min(readerFontSize + Self.fontSizeStep, Self.maxFontSize)
        updateRenderedBlocks(from: document.text)
    }

    private func decreaseFontSize() {
        readerFontSize = max(readerFontSize - Self.fontSizeStep, Self.minFontSize)
        updateRenderedBlocks(from: document.text)
    }

    private func resetFontSize() {
        readerFontSize = Self.defaultFontSize
        updateRenderedBlocks(from: document.text)
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
        let doc = MarkdownParser.parse(text)
        headings = MarkdownParser.extractHeadings(from: doc)
    }

    private func updateRenderedBlocks(from text: String) {
        renderedBlocks = BlockRenderer.render(text, style: renderStyle)
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

    }

    // MARK: - File Watching

    private func setupFileWatcher() {
        guard let url = fileURL else { return }

        // Store initial modification date
        lastKnownModDate = url.fileModificationDate

        // Set up watcher for external changes
        fileWatcher = FileWatcher(url: url) { [self] in
            // Ignore if we're suppressing (our own format/save in progress)
            guard !suppressExternalChangeAlert else {
                lastKnownModDate = url.fileModificationDate
                return
            }

            // Check if file actually changed (not just touched)
            guard let currentModDate = url.fileModificationDate,
                  let lastKnown = lastKnownModDate,
                  currentModDate > lastKnown else {
                return
            }

            // Show alert on main thread
            DispatchQueue.main.async {
                showExternalChangeAlert = true
            }
        }
    }

    private func reloadFromDisk() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        document.text = text
        lastKnownModDate = url.fileModificationDate

        // Re-render
        updateHeadings(from: text)
        updateRenderedBlocks(from: text)
    }

    /// Checks for save conflicts before saving. Returns true if safe to save.
    func checkSaveConflict() -> Bool {
        guard let url = fileURL,
              let currentModDate = url.fileModificationDate,
              let lastKnown = lastKnownModDate else {
            return true // No conflict detection possible, allow save
        }

        if currentModDate > lastKnown {
            // File was modified externally - show conflict dialog
            return false
        }

        return true
    }

    private var readerView: some View {
        ScrollViewReader { proxy in
            ScrollView {
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
                        onScrollProgress: { percent in
                            // Debounce to update on scroll stop
                            percentUpdateTask?.cancel()
                            percentUpdateTask = Task {
                                try? await Task.sleep(nanoseconds: 150_000_000)
                                guard !Task.isCancelled else { return }
                                displayedPercentRead = percent
                            }
                        },
                        onMermaidExpand: { source in expandedMermaidSource = source }
                    )
                    .environment(\.onImageExpand) { imageData in expandedImageData = imageData }
                    .padding(fullWidthReader ? 24 : 40)
                    .frame(maxWidth: fullWidthReader ? .infinity : 720, alignment: .leading)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("reader-scroll")).minY)
                                .onAppear {
                                    contentHeight = geo.size.height
                                }
                                .onChange(of: geo.size.height) { _, newHeight in
                                    contentHeight = newHeight
                                }
                        }
                    )
                }
            }
            .coordinateSpace(name: "reader-scroll")
            .onAppear {
                scrollProxy = proxy
                restoreScrollPosition(proxy: proxy)
            }
            .onDisappear {
                saveScrollPosition()
            }
            .onChange(of: scrollToHeadingIndex) { _, newIndex in
                if let index = newIndex {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("block-\(index)", anchor: .top)
                    }
                    // Reset after scrolling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        scrollToHeadingIndex = nil
                    }
                }
            }
            .onChange(of: currentMatchIndex) { _, newIndex in
                scrollToMatch(newIndex, proxy: proxy)
            }
            .onChange(of: searchMatches.count) { _, _ in
                // Scroll to first match when search results change
                if !searchMatches.isEmpty {
                    scrollToMatch(0, proxy: proxy)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
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
                        onMermaidExpand: { source in expandedMermaidSource = source }
                    )
                    .environment(\.onImageExpand) { imageData in expandedImageData = imageData }
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

/// MARK: - Scroll Position Tracking

private struct ScrollOffsetPreferenceKey: PreferenceKey {
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
