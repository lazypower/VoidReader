import SwiftUI
import VoidReaderCore

struct ContentView: View {
    @Binding var document: MarkdownDocument
    @State private var isEditMode = false

    var body: some View {
        Group {
            if document.text.isEmpty && !isEditMode {
                // Empty document opened without context - go to edit mode
                editorView
                    .onAppear { isEditMode = true }
            } else if isEditMode {
                editorView
            } else {
                readerView
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isEditMode.toggle()
                } label: {
                    Label(
                        isEditMode ? "Read" : "Edit",
                        systemImage: isEditMode ? "book" : "pencil"
                    )
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var readerView: some View {
        ScrollView {
            MarkdownReaderView(text: document.text)
                .padding(40)
                .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var editorView: some View {
        HSplitView {
            // Source editor
            TextEditor(text: $document.text)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 200)

            // Preview
            ScrollView {
                MarkdownReaderView(text: document.text)
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
