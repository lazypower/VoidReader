import SwiftUI
import AppKit
import VoidReaderCore

/// A markdown editor with syntax highlighting using swift-markdown AST.
struct SyntaxHighlightingEditor: NSViewRepresentable {
    @Binding var text: String
    let theme: AppTheme
    let colorScheme: ColorScheme
    var font: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    var onTextChange: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        // Configure text view
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = font
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.backgroundColor = NSColor.textBackgroundColor

        // Set delegate
        textView.delegate = context.coordinator

        // Initial content with highlighting
        applyHighlighting(to: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Check if text changed externally
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            applyHighlighting(to: textView)
            textView.selectedRanges = selectedRanges
        }

        // Check if theme or colorScheme changed
        if context.coordinator.lastThemeID != theme.id ||
           context.coordinator.lastColorScheme != colorScheme {
            context.coordinator.lastThemeID = theme.id
            context.coordinator.lastColorScheme = colorScheme
            applyHighlighting(to: textView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, parent: self)
    }

    private func applyHighlighting(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }

        // Save selection
        let selectedRanges = textView.selectedRanges

        // Get highlighted text
        let highlighted = MarkdownSyntaxHighlighter.highlight(
            textView.string,
            theme: theme,
            colorScheme: colorScheme,
            font: font
        )

        // Replace text storage contents
        textStorage.beginEditing()
        textStorage.setAttributedString(highlighted)
        textStorage.endEditing()

        // Restore selection
        textView.selectedRanges = selectedRanges
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var parent: SyntaxHighlightingEditor
        var lastThemeID: String?
        var lastColorScheme: ColorScheme?
        private var isUpdating = false

        // Debounce timer for re-highlighting
        private var highlightTimer: Timer?

        init(text: Binding<String>, parent: SyntaxHighlightingEditor) {
            self.text = text
            self.parent = parent
            self.lastThemeID = parent.theme.id
            self.lastColorScheme = parent.colorScheme
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }

            isUpdating = true
            text.wrappedValue = textView.string
            parent.onTextChange?()
            isUpdating = false

            // Debounce re-highlighting
            highlightTimer?.invalidate()
            highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.rehighlight(textView)
            }
        }

        private func rehighlight(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }

            // Save state
            let selectedRanges = textView.selectedRanges
            let visibleRect = textView.visibleRect

            // Apply highlighting
            let highlighted = MarkdownSyntaxHighlighter.highlight(
                textView.string,
                theme: parent.theme,
                colorScheme: parent.colorScheme,
                font: parent.font
            )

            isUpdating = true
            textStorage.beginEditing()
            textStorage.setAttributedString(highlighted)
            textStorage.endEditing()
            isUpdating = false

            // Restore state
            textView.selectedRanges = selectedRanges
            textView.scrollToVisible(visibleRect)
        }
    }
}

#Preview {
    SyntaxHighlightingEditor(
        text: .constant("""
        # Hello World

        This is **bold** and *italic* text.

        - List item one
        - [ ] Task unchecked
        - [x] Task checked

        ```swift
        let x = 42
        ```

        > A blockquote

        [Link](https://example.com)
        """),
        theme: .catppuccin,
        colorScheme: .dark
    )
    .frame(width: 500, height: 400)
}
