import SwiftUI
import AppKit
import VoidReaderCore

/// A markdown editor with syntax highlighting using swift-markdown AST.
struct SyntaxHighlightingEditor: NSViewRepresentable {
    @Binding var text: String
    let theme: AppTheme
    let colorScheme: ColorScheme
    var font: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    var lintWarnings: [LintWarning] = []
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

        // TODO: Gutter with line numbers/warnings needs custom container view
        // NSRulerView conflicts with NSTextView.scrollableTextView() layout

        // Accessibility identifier for UI testing
        scrollView.setAccessibilityIdentifier("editor-view")
        textView.setAccessibilityIdentifier("editor-text-view")

        // Setup scroll observation for visible-region rehighlighting on large docs
        context.coordinator.setupScrollObservation(scrollView: scrollView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Refresh the coordinator's snapshot of this representable so the
        // debounced rehighlight reads the LIVE theme/colorScheme/font. Without
        // this the coordinator kept the launch-time copy, and the colors reverted
        // to the old theme on the first keystroke after a theme change.
        context.coordinator.parent = self

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

        let charCount = textView.string.count

        // For large documents, only highlight visible region initially
        // This prevents editor freeze on open
        let isVisibleOnly = charCount > RenderingThresholds.editorVisibleHighlightChars
            && textView.layoutManager != nil
            && textView.textContainer != nil

        // Signpost: syntaxHighlightPass — single interval covering the whole pass, with
        // metadata distinguishing the visible-region fast path from the full-document path.
        let signposter = Signposts.signposter(for: .rendering)
        let signpostID = signposter.makeSignpostID()
        let signpostState = signposter.beginInterval(
            "syntaxHighlightPass",
            id: signpostID,
            "mode=\(isVisibleOnly ? "visible" : "full") chars=\(charCount)"
        )
        defer { signposter.endInterval("syntaxHighlightPass", signpostState) }

        if isVisibleOnly,
           let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            DebugLog.measure(.editor, "applyHighlightingVisible(\(charCount) chars)") {
                applyVisibleHighlighting(to: textView, layoutManager: layoutManager, textContainer: textContainer)
            }
            return
        }

        DebugLog.measure(.editor, "applyHighlightingFull(\(charCount) chars)") {
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
    }

    /// Apply visible-region highlighting for large documents on initial load
    private func applyVisibleHighlighting(to textView: NSTextView, layoutManager: NSLayoutManager, textContainer: NSTextContainer) {
        guard let textStorage = textView.textStorage else { return }

        let fullText = textView.string
        let charCount = fullText.count
        let selectedRanges = textView.selectedRanges

        // Get visible character range (may be 0 on initial load, so use buffer from start)
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Add buffer around visible region
        let buffer = 10_000
        let startChar = max(0, visibleCharRange.location - buffer)
        let endChar = min(charCount, max(visibleCharRange.location + visibleCharRange.length + buffer, buffer * 2))
        let highlightLength = endChar - startChar

        DebugLog.log(.editor, "Visible region: \(highlightLength) of \(charCount) chars (start: \(startChar))")

        // Extract region to highlight
        let startIndex = fullText.index(fullText.startIndex, offsetBy: startChar)
        let endIndex = fullText.index(fullText.startIndex, offsetBy: endChar)
        let regionText = String(fullText[startIndex..<endIndex])

        // Highlight just this region
        let highlighted = MarkdownSyntaxHighlighter.highlight(
            regionText,
            theme: theme,
            colorScheme: colorScheme,
            font: font
        )

        // Apply base styling to entire document (fast - just font + color)
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor
        ]

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttrs, range: NSRange(location: 0, length: charCount))

        // Apply syntax highlighting to visible region
        let nsHighlighted = NSAttributedString(attributedString: highlighted)
        nsHighlighted.enumerateAttributes(in: NSRange(location: 0, length: nsHighlighted.length)) { attrs, range, _ in
            let docRange = NSRange(location: startChar + range.location, length: range.length)
            if docRange.location + docRange.length <= charCount {
                textStorage.setAttributes(attrs, range: docRange)
            }
        }

        textStorage.endEditing()
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

        // Debounce timer for scroll-based rehighlight
        private var scrollHighlightTimer: Timer?

        // Track if initial full highlight was done (for first load)
        private var initialHighlightDone = false

        // Weak reference to scroll view for scroll observation
        weak var scrollView: NSScrollView?

        init(text: Binding<String>, parent: SyntaxHighlightingEditor) {
            self.text = text
            self.parent = parent
            self.lastThemeID = parent.theme.id
            self.lastColorScheme = parent.colorScheme
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        /// Setup scroll observation for rehighlighting on scroll
        func setupScrollObservation(scrollView: NSScrollView) {
            self.scrollView = scrollView

            // Observe scroll changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollViewDidScroll(_:)),
                name: NSScrollView.didLiveScrollNotification,
                object: scrollView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(scrollViewDidEndScroll(_:)),
                name: NSScrollView.didEndLiveScrollNotification,
                object: scrollView
            )
        }

        @objc private func scrollViewDidScroll(_ notification: Notification) {
            // During scroll, cancel pending rehighlight to avoid lag
            scrollHighlightTimer?.invalidate()
        }

        @objc private func scrollViewDidEndScroll(_ notification: Notification) {
            guard let scrollView = notification.object as? NSScrollView,
                  let textView = scrollView.documentView as? NSTextView,
                  textView.string.count > RenderingThresholds.editorVisibleHighlightChars else { return }

            // Debounce scroll-end rehighlight (100ms after scroll stops)
            scrollHighlightTimer?.invalidate()
            scrollHighlightTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.rehighlightVisibleRegion(textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }

            // Only update binding if text actually changed (avoids false dirty on highlight)
            let newText = textView.string
            guard newText != text.wrappedValue else { return }

            isUpdating = true
            text.wrappedValue = newText
            parent.onTextChange?()
            isUpdating = false

            // Debounce re-highlighting
            highlightTimer?.invalidate()
            highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.rehighlight(textView)
            }
        }

        private func rehighlight(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }

            let charCount = textView.string.count

            // For large documents (>50K chars), only highlight visible region + buffer
            // This dramatically improves editing performance
            if charCount > RenderingThresholds.editorVisibleHighlightChars {
                rehighlightVisibleRegion(textView)
            } else {
                rehighlightFull(textView)
            }
        }

        /// Full document rehighlight (for small documents)
        private func rehighlightFull(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }

            let charCount = textView.string.count
            DebugLog.measure(.editor, "rehighlightFull(\(charCount) chars)") {
                let selectedRanges = textView.selectedRanges
                let visibleRect = textView.visibleRect

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

                textView.selectedRanges = selectedRanges
                textView.scrollToVisible(visibleRect)
            }
        }

        /// Visible region rehighlight (for large documents)
        /// Only highlights the visible text + a buffer, much faster for large docs
        private func rehighlightVisibleRegion(_ textView: NSTextView) {
            guard let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let fullText = textView.string
            let charCount = fullText.count

            // Get visible character range
            let visibleRect = textView.visibleRect
            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            let visibleCharRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

            // Add buffer around visible region (5000 chars each side)
            let buffer = 5000
            let startChar = max(0, visibleCharRange.location - buffer)
            let endChar = min(charCount, visibleCharRange.location + visibleCharRange.length + buffer)
            let highlightLength = endChar - startChar

            DebugLog.measure(.editor, "rehighlightVisible(\(highlightLength) of \(charCount) chars)") {
                let selectedRanges = textView.selectedRanges

                // Extract the region to highlight
                let startIndex = fullText.index(fullText.startIndex, offsetBy: startChar)
                let endIndex = fullText.index(fullText.startIndex, offsetBy: endChar)
                let regionText = String(fullText[startIndex..<endIndex])

                // Highlight just this region
                let highlighted = MarkdownSyntaxHighlighter.highlight(
                    regionText,
                    theme: parent.theme,
                    colorScheme: parent.colorScheme,
                    font: parent.font
                )

                isUpdating = true
                textStorage.beginEditing()

                // Apply base styling to entire document first (fast)
                let baseAttrs: [NSAttributedString.Key: Any] = [
                    .font: parent.font,
                    .foregroundColor: NSColor.textColor
                ]
                textStorage.setAttributes(baseAttrs, range: NSRange(location: 0, length: charCount))

                // Now apply syntax highlighting to the visible region by copying attributes
                let nsHighlighted = NSAttributedString(attributedString: highlighted)
                nsHighlighted.enumerateAttributes(in: NSRange(location: 0, length: nsHighlighted.length)) { attrs, range, _ in
                    // Offset the range to the correct position in the full document
                    let docRange = NSRange(location: startChar + range.location, length: range.length)
                    if docRange.location + docRange.length <= charCount {
                        textStorage.setAttributes(attrs, range: docRange)
                    }
                }

                textStorage.endEditing()
                isUpdating = false

                textView.selectedRanges = selectedRanges
            }
        }
    }
}

