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

    // For print/export/share commands
    private let printPublisher = NotificationCenter.default.publisher(for: .printDocument)
    private let exportPDFPublisher = NotificationCenter.default.publisher(for: .exportPDF)
    private let sharePublisher = NotificationCenter.default.publisher(for: .shareDocument)

    // Share sheet state
    @State private var showingShare = false

    // Scroll position tracking
    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollProxy: ScrollViewProxy?

    // Find bar
    @State private var showFindBar = false
    @State private var showReplace = false
    @State private var searchText = ""
    @State private var replaceText = ""
    @State private var searchMatches: [TextSearcher.Match] = []
    @State private var currentMatchIndex = 0

    // Cached rendered blocks (expensive to compute)
    @State private var renderedBlocks: [MarkdownBlock] = []

    // Mermaid expand overlay
    @State private var expandedMermaidSource: String?

    // File watching and conflict detection
    @State private var fileWatcher: FileWatcher?
    @State private var lastKnownModDate: Date?
    @State private var showExternalChangeAlert = false
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
            } else {
                normalView
            }
        }
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
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expandedMermaidSource != nil)
        .cheatSheetOnHold(isShowing: $showCheatSheet)
        .onAppear {
            setupDebouncing()
        }
        .onChange(of: document.text) { _, newValue in
            // Send to debounce publisher for preview
            textUpdatePublisher.send(newValue)
            // Update stats immediately (cheap operation)
            documentStats = DocumentStats(text: newValue)
            // Update headings for outline
            updateHeadings(from: newValue)
            // Update cached blocks
            updateRenderedBlocks(from: newValue)
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
        .onChange(of: searchText) { _, _ in
            updateSearch()
        }
        .background(
            ShareSheetPresenter(isPresented: $showingShare, items: [document.text])
        )
        .background(
            // Keyboard shortcuts for Find/Replace
            Group {
                Button("") { showFind() }
                    .keyboardShortcut("f", modifiers: .command)
                Button("") { showFindAndReplace() }
                    .keyboardShortcut("h", modifiers: .command)
            }
            .hidden()
        )
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
                        matchCount: searchMatches.count,
                        currentMatch: searchMatches.isEmpty ? 0 : currentMatchIndex + 1,
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
                    StatusBarView(stats: documentStats)
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditMode.toggle()
                    }
                    if isEditMode {
                        // Focus editor after animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            isEditorFocused = true
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
        renderedBlocks = BlockRenderer.render(text)
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
                let matches = TextSearcher.findMatches(query: searchText, in: blockText)
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
        let matches = TextSearcher.findMatches(query: searchText, in: document.text)
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
        let matches = TextSearcher.findMatches(query: searchText, in: document.text)
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
            in: renderedBlocks
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo("block-\(blockIdx)", anchor: .center)
            }
        }
    }

    private func setupDebouncing() {
        textUpdatePublisher
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { newText in
                debouncedText = newText
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
                        searchText: searchText,
                        currentMatchIndex: currentMatchIndex,
                        onTaskToggle: handleTaskToggle,
                        onTopBlockChange: updateCurrentHeading,
                        onMermaidExpand: { source in expandedMermaidSource = source }
                    )
                    .padding(40)
                    .frame(maxWidth: 720, alignment: .leading)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("reader-scroll")).minY)
                                .onAppear {
                                    contentHeight = geo.size.height
                                }
                        }
                    )
                }
            }
            .coordinateSpace(name: "reader-scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                scrollOffset = -offset
            }
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

    private var editorView: some View {
        HSplitView {
            // Source editor
            TextEditor(text: $document.text)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 200)
                .focused($isEditorFocused)

            // Preview (uses debounced text and cached blocks for performance)
            ScrollViewReader { proxy in
                ScrollView {
                    MarkdownReaderViewWithAnchors(
                        text: debouncedText,
                        headings: headings,
                        blocks: renderedBlocks,
                        onTaskToggle: handleTaskToggle,
                        onMermaidExpand: { source in expandedMermaidSource = source }
                    )
                    .padding(40)
                    .frame(maxWidth: 720, alignment: .leading)
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
            .frame(minWidth: 200)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

// MARK: - Scroll Position Tracking

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
