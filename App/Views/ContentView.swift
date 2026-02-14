import SwiftUI
import VoidReaderCore
import Combine

struct ContentView: View {
    @Binding var document: MarkdownDocument
    @State private var isEditMode = false
    @AppStorage("showStatusBar") private var showStatusBar = true
    @State private var showCheatSheet = false
    @State private var isDistractionFree = false
    @State private var documentStats: DocumentStats
    @State private var debouncedText: String
    @FocusState private var isEditorFocused: Bool

    // Debounce publisher for preview updates
    @State private var textUpdatePublisher = PassthroughSubject<String, Never>()
    @State private var cancellables = Set<AnyCancellable>()

    init(document: Binding<MarkdownDocument>) {
        self._document = document
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
        }
    }

    private var normalView: some View {
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
        .toolbar {
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
        ScrollView {
            MarkdownReaderView(text: document.text, onTaskToggle: handleTaskToggle)
                .padding(40)
                .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
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
