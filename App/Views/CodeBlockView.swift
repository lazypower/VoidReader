import SwiftUI
import VoidReaderCore
import Highlightr
import AppKit

/// Shared highlighter instance for performance.
private let highlightr: Highlightr? = {
    let h = Highlightr()
    return h
}()

/// Renders a code block with syntax highlighting and copy button.
///
/// ## Threading
/// `Highlightr` runs JavaScript inside a `JSContext` and was previously called
/// synchronously on the main thread, which beachballed the UI for ~5s per
/// ~1.5MB block while highlight.js chewed through tokens. Highlight work now
/// runs on `highlightQueue` (a dedicated serial queue — `Highlightr`'s
/// `JSContext` has thread affinity, so every call to the shared instance must
/// funnel through one thread) and the result is published back to the view's
/// `@State` on the main thread. Brief plain-text flash on first appear is the
/// accepted tradeoff.
///
/// ## Large blocks
/// SwiftUI `Text` cannot lay out multi-MB strings during lazy scroll layout
/// without blocking the main thread (independent of any highlighting). Above
/// `maxHighlightableChars`, the content area swaps to `CodeTextView`
/// (`NSTextView` via `NSViewRepresentable`), which uses TextKit and handles
/// arbitrary sizes cleanly. Above-threshold blocks render plain monospaced —
/// matching highlighting would require streaming/chunked highlight that's out
/// of scope for this fix.
struct CodeBlockView: View {
    /// Threshold above which we switch the view path to `NSTextView`.
    /// SwiftUI `Text` computes intrinsic content size eagerly over the full
    /// string before it can measure its frame — so large blocks beachball on
    /// initial paint, independent of whether the content is plain or
    /// highlighted. TextKit (NSTextView) lays out lazily per line fragment
    /// and handles any size cleanly. 50KB is a conservative knee that keeps
    /// normal-sized code blocks on the SwiftUI path while routing anything
    /// meaningfully large to TextKit. This is a *layout* concern, separate
    /// from the highlight ceiling below.
    private static let maxSwiftUITextChars = 50_000

    /// Safety ceiling on highlight work itself. Empirically, the highlighted
    /// `NSAttributedString` weighs ~160x the raw bytes (attribute runs per
    /// token + retained JSC heap). A 3MB block highlighted costs ~490MB of
    /// RAM. 1MB caps single-block cost at ~160MB — chunky but tolerable —
    /// while still covering every realistic hand-written block. Multi-block
    /// docs pay this tax per block, so truly large pasted/generated content
    /// stays plain intentionally.
    private static let maxHighlightChars = 1_000_000

    /// Dedicated queue for `Highlightr` work. `JSContext` has thread affinity,
    /// so every call to the shared `highlightr` instance must run on this
    /// queue.
    private static let highlightQueue = DispatchQueue(
        label: "place.wabash.VoidReader.highlight",
        qos: .userInitiated
    )

    let data: CodeBlockData
    var fontSize: CGFloat = 13
    var fontFamily: String? = nil  // nil = system mono
    @State private var showCopied = false
    @State private var cachedHighlight: AttributedString?
    @State private var cacheKey: String = ""
    @State private var requestSeq: Int = 0
    @State private var nsTextHeight: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    // Theme config - single point to change later
    private var themeName: String {
        colorScheme == .dark ? "atom-one-dark" : "atom-one-light"
    }

    // Badge font scales with code font
    private var badgeFontSize: CGFloat {
        max(9, fontSize * 0.85)
    }

    // Resolve font family to NSFont
    private var nsFont: NSFont {
        if let family = fontFamily, let font = NSFont(name: family, size: fontSize) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    /// Use the `NSTextView`-backed renderer instead of SwiftUI `Text` — purely
    /// a layout decision. Highlighting still runs for these blocks (up to
    /// `maxHighlightChars`), and the result is piped into the text view.
    private var useNSTextView: Bool {
        data.code.count > Self.maxSwiftUITextChars
    }

    /// Whether this block is small enough to attempt highlighting at all.
    private var canHighlight: Bool {
        data.code.count <= Self.maxHighlightChars
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language badge + copy button
            HStack {
                if let language = data.language, !language.isEmpty {
                    Text(language)
                        .font(.system(size: badgeFontSize, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                        .cornerRadius(4)
                }

                Spacer()

                Button(action: copyCode) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        if showCopied {
                            Text("Copied")
                                .font(.system(size: badgeFontSize))
                        }
                    }
                    .foregroundColor(showCopied ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Code content — engine swaps based on size.
            codeContent
        }
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
        .cornerRadius(8)
        .onAppear { updateHighlightCache() }
        .onChange(of: colorScheme) { _, _ in updateHighlightCache() }
        .onDisappear {
            // Drop the cached highlight when the block scrolls out of the
            // lazy viewport. LazyVStack usually tears down rows off-screen
            // (which releases @State anyway), but SwiftUI can keep views
            // around briefly for reuse — explicit eviction ensures the
            // attributed string's memory is reclaimed promptly. On re-appear,
            // `onAppear` + the `key != cacheKey` check re-enqueues highlight
            // work; the stale-result guard in `updateHighlightCache` handles
            // fast back-and-forth scrolling without incorrect output.
            cachedHighlight = nil
            cacheKey = ""
        }
    }

    @ViewBuilder
    private var codeContent: some View {
        if useNSTextView {
            // Above layout threshold: NSTextView wraps its own NSScrollView
            // for horizontal panning, so we don't nest in a SwiftUI
            // ScrollView. Height is bridged from TextKit's used rect via
            // @State. Highlighted AttributedString is piped in when it lands
            // from the off-main highlight queue — initial paint is plain and
            // swaps when ready ("pop-in").
            CodeTextView(
                text: data.code,
                font: nsFont,
                highlighted: cachedHighlight,
                contentHeight: $nsTextHeight
            )
            .frame(height: max(nsTextHeight, fontSize + 16))
            .padding(12)
        } else {
            // Below threshold: SwiftUI Text + Highlightr (off-main).
            ScrollView(.horizontal, showsIndicators: false) {
                highlightedCode
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
    }

    /// Key that invalidates the highlight cache when inputs change.
    private var highlightKey: String {
        "\(data.code.hashValue)-\(themeName)-\(fontSize)-\(fontFamily ?? "")"
    }

    /// Mono font for the SwiftUI `Text` path. The cached `AttributedString`
    /// carries only foreground-color runs (attribute diet, see
    /// `updateHighlightCache`), so the font must be applied externally.
    private var swiftUIFont: Font {
        fontFamily.flatMap { Font.custom($0, size: fontSize) }
            ?? .system(size: fontSize, design: .monospaced)
    }

    @ViewBuilder
    private var highlightedCode: some View {
        if let highlighted = cachedHighlight {
            Text(highlighted).font(swiftUIFont)
        } else {
            // Shown briefly while off-main highlight runs (or if it failed).
            Text(data.code).font(swiftUIFont)
        }
    }

    private func updateHighlightCache() {
        let key = highlightKey
        guard key != cacheKey else { return }

        // Skip only truly pathological sizes — everything else attempts
        // highlighting and pops in when ready. Layout path is chosen
        // separately via `useNSTextView`.
        guard canHighlight else { return }

        guard highlightr != nil else { return }

        // Snapshot inputs for the background closure — `self` is a struct, so
        // these are stable copies. Writes go back through @State on main.
        let codeSnapshot = data.code
        let language = data.language?.lowercased()
        let theme = themeName

        // Stale-result guard: bump a monotonic counter on each dispatch and
        // compare on apply. If a newer request landed first (e.g. user toggled
        // dark mode while the previous highlight was still running), discard.
        requestSeq &+= 1
        let mySeq = requestSeq

        Self.highlightQueue.async {
            // JSContext access — must be on this queue.
            guard let highlightr = highlightr else { return }
            highlightr.setTheme(to: theme)
            guard let nsAttr = highlightr.highlight(codeSnapshot, as: language) else { return }

            // Attribute diet: keep only `.foregroundColor` runs. Font is
            // applied externally (via `swiftUIFont` modifier on the SwiftUI
            // path, and `textView.font` on the NSTextView path). Dropping
            // per-run font attributes lets NSAttributedString coalesce
            // adjacent runs that share a color — a big memory win for
            // token-dense code, where highlight.js emits one run per
            // identifier/keyword.
            let slim = NSMutableAttributedString(string: nsAttr.string)
            let fullRange = NSRange(location: 0, length: nsAttr.length)
            nsAttr.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                if let color = value as? NSColor {
                    slim.addAttribute(.foregroundColor, value: color, range: range)
                }
            }
            let result = try? AttributedString(slim, including: AttributeScopes.AppKitAttributes.self)

            DispatchQueue.main.async {
                guard mySeq == requestSeq else { return }
                cachedHighlight = result
                cacheKey = key
            }
        }
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(data.code, forType: .string)

        withAnimation {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopied = false
            }
        }
    }
}

// MARK: - NSTextView wrapper for large code blocks

/// AppKit-backed code renderer for large blocks where SwiftUI `Text` would
/// block the main thread during layout. Wraps `NSTextView` inside an
/// `NSScrollView` configured for horizontal scrolling with no word wrap, so
/// long lines pan instead of wrapping (matching the SwiftUI path's behavior).
/// Reports its laid-out height back to the SwiftUI parent via `contentHeight`
/// so the parent `LazyVStack` row sizes correctly.
private struct CodeTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    /// Optional highlighted result from the off-main highlight queue. When
    /// present, used instead of the plain-font attributed string.
    let highlighted: AttributedString?
    @Binding var contentHeight: CGFloat

    final class Coordinator {
        var lastTextHash: Int = 0
        var lastFont: NSFont?
        var lastHighlightHash: Int = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = font
        textView.textColor = .textColor

        // Let content grow horizontally beyond the viewport so the scroll view
        // pans rather than wrapping long lines.
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.autoresizingMask = [.width]

        if let container = textView.textContainer {
            container.widthTracksTextView = false
            container.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            container.lineFragmentPadding = 0
        }

        scrollView.documentView = textView
        applyText(to: textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        applyText(to: textView, coordinator: context.coordinator)
    }

    /// Set text + font on the NSTextView and report computed height to SwiftUI.
    /// Deduped via the coordinator so SwiftUI's frequent `updateNSView` calls
    /// don't re-set multi-MB attributedStrings on every pass.
    private func applyText(to textView: NSTextView, coordinator: Coordinator) {
        let textHash = text.hashValue
        let highlightHash = highlighted?.hashValue ?? 0
        let fontChanged = coordinator.lastFont != font
        let textChanged = coordinator.lastTextHash != textHash
        let highlightChanged = coordinator.lastHighlightHash != highlightHash

        guard textChanged || fontChanged || highlightChanged else { return }

        textView.font = font
        let attributed: NSAttributedString
        if let highlighted {
            // Highlighted path — font is already baked in by the highlight
            // queue's font-merge pass.
            attributed = NSAttributedString(highlighted)
        } else {
            // Plain path (initial paint, or blocks above `maxHighlightChars`).
            attributed = NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.textColor
                ]
            )
        }
        textView.textStorage?.setAttributedString(attributed)

        coordinator.lastTextHash = textHash
        coordinator.lastFont = font
        coordinator.lastHighlightHash = highlightHash

        // Force layout so usedRect reflects actual content, then bridge the
        // height back. ensureLayout on TextKit is significantly faster than
        // SwiftUI Text's intrinsic-size path for large strings — that's the
        // whole reason this view exists. Async to avoid mutating SwiftUI state
        // mid-update (would log purple warnings in debug builds).
        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer)
            let newHeight = ceil(used.height)
            DispatchQueue.main.async {
                if abs(contentHeight - newHeight) > 0.5 {
                    contentHeight = newHeight
                }
            }
        }
    }
}

#Preview("Swift") {
    CodeBlockView(data: CodeBlockData(
        code: """
        func greet(name: String) -> String {
            return "Hello, \\(name)!"
        }

        let message = greet(name: "World")
        print(message)
        """,
        language: "swift"
    ))
    .padding()
    .frame(width: 500)
}

#Preview("Python") {
    CodeBlockView(data: CodeBlockData(
        code: """
        def fibonacci(n):
            if n <= 1:
                return n
            return fibonacci(n-1) + fibonacci(n-2)

        for i in range(10):
            print(fibonacci(i))
        """,
        language: "python"
    ))
    .padding()
    .frame(width: 500)
}

#Preview("No Language") {
    CodeBlockView(data: CodeBlockData(
        code: "Some plain text code without language hint",
        language: nil
    ))
    .padding()
    .frame(width: 500)
}
