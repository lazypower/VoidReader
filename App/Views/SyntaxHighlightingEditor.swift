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
            DebugLog.measure(.editor, "rehighlight(\(charCount) chars)") {
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
}

// MARK: - Gutter View

/// A gutter view that displays line numbers and warning indicators.
class GutterView: NSRulerView {
    weak var textView: NSTextView?
    var warnings: [LintWarning] = [] {
        didSet { updateWarningsByLine() }
    }
    private var warningsByLine: [Int: LintWarning.Severity] = [:]

    private let gutterWidth: CGFloat = 36
    private let warningDotSize: CGFloat = 8

    init(scrollView: NSScrollView, textView: NSTextView, warnings: [LintWarning] = []) {
        self.textView = textView
        self.warnings = warnings
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.ruleThickness = gutterWidth
        self.clientView = textView
        updateWarningsByLine()

        // Observe text changes to update gutter
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func textDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    private func updateWarningsByLine() {
        warningsByLine = [:]
        for warning in warnings {
            // Keep the highest severity for each line
            if let existing = warningsByLine[warning.line] {
                if warning.severity == .error || existing == .warning {
                    warningsByLine[warning.line] = warning.severity
                }
            } else {
                warningsByLine[warning.line] = warning.severity
            }
        }
    }


    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = textView.visibleRect
        let textInset = textView.textContainerInset

        // Background
        NSColor.windowBackgroundColor.setFill()
        rect.fill()

        // Separator line
        NSColor.separatorColor.setStroke()
        let separatorPath = NSBezierPath()
        separatorPath.move(to: NSPoint(x: rect.maxX - 0.5, y: rect.minY))
        separatorPath.line(to: NSPoint(x: rect.maxX - 0.5, y: rect.maxY))
        separatorPath.stroke()

        // Text attributes for line numbers
        let lineNumberAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        // Calculate visible line range
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Get line numbers
        let text = textView.string as NSString
        var lineNumber = 1
        var index = 0

        // Count lines before visible range
        while index < characterRange.location && index < text.length {
            if text.character(at: index) == UInt16(Character("\n").asciiValue!) {
                lineNumber += 1
            }
            index += 1
        }

        // Draw visible lines
        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

            // Adjust for text inset and scroll position
            let yPosition = lineRect.minY + textInset.height - visibleRect.minY

            // Draw warning dot if present
            if let severity = warningsByLine[lineNumber] {
                let dotColor: NSColor = severity == .error ? .systemRed : .systemYellow
                let dotRect = NSRect(
                    x: 4,
                    y: yPosition + (lineRect.height - warningDotSize) / 2,
                    width: warningDotSize,
                    height: warningDotSize
                )
                dotColor.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }

            // Draw line number
            let lineNumberString = "\(lineNumber)" as NSString
            let stringSize = lineNumberString.size(withAttributes: lineNumberAttributes)
            let stringRect = NSRect(
                x: gutterWidth - stringSize.width - 8,
                y: yPosition + (lineRect.height - stringSize.height) / 2,
                width: stringSize.width,
                height: stringSize.height
            )
            lineNumberString.draw(in: stringRect, withAttributes: lineNumberAttributes)

            // Move to next line
            var nextGlyphIndex = glyphIndex
            while nextGlyphIndex < NSMaxRange(glyphRange) {
                let nextCharIndex = layoutManager.characterIndexForGlyph(at: nextGlyphIndex)
                if nextCharIndex >= text.length { break }
                if text.character(at: nextCharIndex) == UInt16(Character("\n").asciiValue!) {
                    lineNumber += 1
                    nextGlyphIndex += 1
                    break
                }
                nextGlyphIndex += 1
            }

            if nextGlyphIndex == glyphIndex {
                break
            }
            glyphIndex = nextGlyphIndex
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
