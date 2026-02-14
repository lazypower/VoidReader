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
        }
        .onAppear {
            updateHeadings(from: document.text)
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
        .background(
            ShareSheetPresenter(isPresented: $showingShare, items: [document.text])
        )
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

    private func scrollToHeading(_ heading: HeadingInfo) {
        selectedHeadingID = heading.id
        // Find which block contains this heading and scroll there
        if let blockIdx = MarkdownReaderViewWithAnchors.blockIndex(for: heading.text, in: document.text) {
            scrollToHeadingIndex = blockIdx
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

    private var readerView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Anchor at top for scroll restoration
                    Color.clear.frame(height: 1).id("top")

                    MarkdownReaderViewWithAnchors(
                        text: document.text,
                        headings: headings,
                        onTaskToggle: handleTaskToggle
                    )
                    .padding(40)
                    .frame(maxWidth: 720, alignment: .leading)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scroll")).minY)
                                .onAppear {
                                    contentHeight = geo.size.height
                                }
                        }
                    )
                }
            }
            .coordinateSpace(name: "scroll")
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

            // Preview (uses debounced text for performance)
            ScrollView {
                MarkdownReaderView(text: debouncedText, onTaskToggle: handleTaskToggle)
                    .padding(40)
                    .frame(maxWidth: 720, alignment: .leading)
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
