import SwiftUI
import VoidReaderCore
import Highlightr
import AppKit

/// Shared highlighter instance for the small-block path. The large-block path
/// uses `CodeBlockMeasurementScheduler.highlighter` for the same reason (single
/// shared instance + single queue for JSContext thread affinity).
private let highlightr: Highlightr? = {
    let h = Highlightr()
    return h
}()

/// Renders a code block with syntax highlighting and copy button.
///
/// ## Two rendering paths
/// - **Small blocks** (< `maxSwiftUITextChars`): SwiftUI `Text` with off-main
///   highlighting via `Highlightr`. `Text` sizes itself; no measurement needed.
/// - **Large blocks** (≥ `maxSwiftUITextChars`): `NSTextView` (TextKit)
///   inside a fixed-height frame. The frame height comes from an off-main
///   measurement performed before the view ever commits to a layout. This
///   eliminates the async height-mutation cycle that caused scroll-position
///   drift near the end of large documents.
///
/// ## Why measure off-main first
/// `NSTextView`'s TextKit layout for multi-line code is cheap (~ms), but
/// `usedRect(for:)` can only be read after `ensureLayout`. Historically we
/// called this on a live `NSTextView` inside `makeNSView` and published the
/// height back via `@Binding` — SwiftUI laid the row out once at a
/// placeholder height, then again at the real height when the bridge fired.
/// Repeated across hundreds of blocks in a large doc, the cumulative height
/// shift made scroll-percentage math unstable. The measure-first design
/// renders at a known-stable height from the first frame.
struct CodeBlockView: View {
    // MARK: - Layout constants (shared with height estimation)

    /// Padding above the code area on first/non-segmented blocks.
    static let codeTopPadding: CGFloat = 12
    /// Padding below the code area on last/non-segmented blocks.
    static let codeBottomPadding: CGFloat = 12
    /// Approximate height of the language badge + copy button header.
    static let headerHeight: CGFloat = 24

    /// Total non-code "chrome" height for a code block segment.
    /// Used by `DocumentHeightIndex.defaultFallback` and
    /// `ContentView.recordCodeBlockHeight` so height estimates stay
    /// in sync with the actual view layout.
    static func chromeHeight(isFirst: Bool, isLast: Bool) -> CGFloat {
        var h: CGFloat = 0
        if isFirst { h += codeTopPadding + headerHeight }
        if isLast { h += codeBottomPadding }
        return h
    }

    /// Threshold above which we switch the view path to `NSTextView`.
    /// SwiftUI `Text` computes intrinsic content size eagerly over the full
    /// string — fine for typical code, beachballs for large blocks. 50KB
    /// is the empirical knee. This is a *layout* threshold, distinct from
    /// `maxHighlightChars` below.
    static let maxSwiftUITextChars = 50_000

    /// Safety ceiling on highlight work. The highlighted
    /// `NSAttributedString` weighs ~160x the raw bytes (attribute runs per
    /// token + retained JSC heap). 1MB caps single-block cost at ~160MB —
    /// chunky but tolerable — while still covering every realistic
    /// hand-written block. See `CodeBlockMeasurement.maxHighlightChars`
    /// which mirrors this on the off-main path.
    static let maxHighlightChars = 1_000_000

    /// Dedicated queue for the small-block highlight path.  Large blocks
    /// route through `CodeBlockMeasurementScheduler.queue` instead.
    private static let highlightQueue = DispatchQueue(
        label: "place.wabash.VoidReader.highlight",
        qos: .userInitiated
    )

    let data: CodeBlockData
    var fontSize: CGFloat = 13
    var fontFamily: String? = nil  // nil = system mono

    /// Document-scoped measurement cache, injected via `.environment(\.codeBlockMeasurementCache, ...)`.
    /// `nil` in previews — large-block path falls back to direct on-demand
    /// measurement without a shared cache (still works, just no prefetch benefit).
    @Environment(\.codeBlockMeasurementCache) private var measurementCache
    @State private var showCopied = false
    // Small-block path state
    @State private var cachedHighlight: AttributedString?
    @State private var cacheKey: String = ""
    @State private var requestSeq: Int = 0
    // Large-block path state: the authoritative (attributed, height) pair
    // delivered by the measurement cache. `nil` while measurement is in
    // flight (placeholder shown).
    @State private var measurement: CodeBlockMeasurementResult?
    @Environment(\.colorScheme) private var colorScheme

    // Theme config - single point to change later
    private var themeName: String {
        Self.themeName(for: colorScheme)
    }

    /// Maps SwiftUI `ColorScheme` to the `Highlightr` theme name. Exposed as
    /// a static helper so prefetch paths (in `ContentView`) can resolve the
    /// same theme without re-instantiating a view.
    static func themeName(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? "atom-one-dark" : "atom-one-light"
    }

    /// Same font resolution as the instance property, exposed for prefetch.
    static func nsFont(family: String?, size: CGFloat) -> NSFont {
        if let family, let font = NSFont(name: family, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // Badge font scales with code font
    private var badgeFontSize: CGFloat {
        max(9, fontSize * 0.85)
    }

    // Resolve font family to NSFont
    private var nsFont: NSFont {
        Self.nsFont(family: fontFamily, size: fontSize)
    }

    /// Use the `NSTextView`-backed renderer instead of SwiftUI `Text`.
    ///
    /// Keyed on the *original* (pre-segmentation) block size, not `code.count`.
    /// Segmented rows each hold only their slice (~800 lines / ~30KB), which
    /// slips under the raw threshold — but the visual total is the full parent
    /// block, which is exactly the "large" case this gate exists to catch.
    /// Without this, a 200KB block split into 9 slices routes every slice
    /// through SwiftUI `Text`, saturating the main thread with
    /// `StyledTextLayoutEngine` / CoreText re-measurement during scroll.
    private var useNSTextView: Bool {
        data.originalBlockSize > Self.maxSwiftUITextChars
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language badge + copy button — rendered only on the first
            // segment of a group (or on any non-segmented block). Middle /
            // last segments stay headerless so the visual block looks like
            // one continuous fence.
            if data.isSegmentFirst {
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
            }

            // Code content — engine swaps based on size.
            codeContent
        }
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
        .clipShape(backgroundShape)
        .onAppear { onAppearOrInvalidate() }
        .onChange(of: colorScheme) { _, _ in onAppearOrInvalidate() }
        .onDisappear {
            // Drop @State-local caches when the block scrolls out. The
            // shared `measurementCache` stays warm — so re-entry re-resolves
            // from the cache with zero extra work (no highlight, no
            // re-measure, no visible swap).
            cachedHighlight = nil
            cacheKey = ""
            measurement = nil
        }
    }

    @ViewBuilder
    private var codeContent: some View {
        if useNSTextView {
            largeBlockContent
        } else {
            smallBlockContent
        }
    }

    @ViewBuilder
    private var largeBlockContent: some View {
        if let measurement {
            // Authoritative render path. Frame height is exactly what
            // TextKit will lay out, so there's no post-paint shift.
            CodeTextView(
                text: data.code,
                font: nsFont,
                highlighted: measurement.attributed
            )
            .frame(height: measurement.height)
            .padding(.horizontal, 12)
            .padding(.top, codeTopPad)
            .padding(.bottom, codeBottomPad)
        } else {
            // Placeholder while measurement is in flight. Deterministic,
            // non-zero height so the LazyVStack row has a predictable
            // footprint — not "exactly right," but stable. On measurement
            // landing we swap once to the authoritative height.
            Color.clear
                .frame(height: placeholderHeight)
                .padding(.horizontal, 12)
                .padding(.top, codeTopPad)
                .padding(.bottom, codeBottomPad)
        }
    }

    @ViewBuilder
    private var smallBlockContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            highlightedCode
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.top, codeTopPad)
                .padding(.bottom, codeBottomPad)
        }
    }

    /// Top padding for the code content. Non-segmented blocks and segment-
    /// first blocks get the 12pt breathing room below the header; middle
    /// and last segments render flush so adjacent segments look continuous.
    private var codeTopPad: CGFloat {
        data.isSegmentFirst ? Self.codeTopPadding : 0
    }

    /// Bottom padding mirrors the top rule — last segment (or a non-
    /// segmented block) gets 12pt so the fence closes cleanly; middle
    /// segments stay flush.
    private var codeBottomPad: CGFloat {
        data.isSegmentLast ? Self.codeBottomPadding : 0
    }

    /// Corner-rounded mask that keeps the visual group looking like one
    /// continuous code fence even though it's many LazyVStack rows: first
    /// segment rounds top corners only, last rounds bottom only, middles
    /// stay square, non-segmented blocks round all four.
    private var backgroundShape: UnevenRoundedRectangle {
        let radius: CGFloat = 8
        return UnevenRoundedRectangle(
            topLeadingRadius: data.isSegmentFirst ? radius : 0,
            bottomLeadingRadius: data.isSegmentLast ? radius : 0,
            bottomTrailingRadius: data.isSegmentLast ? radius : 0,
            topTrailingRadius: data.isSegmentFirst ? radius : 0
        )
    }

    /// Deterministic placeholder height for the large-block gate. Uses the
    /// font's line metrics × newline count — not perfectly equal to
    /// TextKit's measured height (paragraph spacing, leading quirks), but
    /// stable for a given (code, font, size) tuple, which is what matters
    /// during the brief measurement window.
    private var placeholderHeight: CGFloat {
        var lineCount = 1
        for char in data.code where char == "\n" {
            lineCount += 1
        }
        let lineHeight = ceil(nsFont.ascender - nsFont.descender + nsFont.leading)
        return CGFloat(lineCount) * lineHeight
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
            Text(data.code).font(swiftUIFont)
        }
    }

    /// Router — called on appear and on any input change that could
    /// invalidate the cache (color scheme flip, re-entry after disappear).
    /// Each path is idempotent: cached results short-circuit immediately.
    private func onAppearOrInvalidate() {
        if useNSTextView {
            requestMeasurement()
        } else {
            updateHighlightCache()
        }
    }

    /// Resolve the block's measurement from the document-scoped cache.
    /// Cache hit → immediate render at authoritative height. Miss → enqueue
    /// off-main work; placeholder renders until result lands on main.
    private func requestMeasurement() {
        guard let cache = measurementCache else { return }
        let fontName = fontFamily ?? ""
        let key = CodeBlockMeasurementKey(
            code: data.code,
            fontName: fontName,
            fontSize: fontSize,
            themeName: themeName
        )

        // Fast cache-hit path: avoid dispatching anything if the prefetch
        // has already measured this block.
        Task {
            if let existing = await cache.get(key) {
                await MainActor.run { measurement = existing }
                return
            }

            CodeBlockMeasurementScheduler.enqueueIfNeeded(
                code: data.code,
                language: data.language,
                fontName: fontName,
                fontSize: fontSize,
                themeName: themeName,
                cache: cache
            ) { resultKey, result in
                // Stale-result guard: if color scheme / font / content
                // changed between dispatch and completion, the key will no
                // longer match the view's current state — drop the result.
                let currentKey = CodeBlockMeasurementKey(
                    code: data.code,
                    fontName: fontFamily ?? "",
                    fontSize: fontSize,
                    themeName: themeName
                )
                guard resultKey == currentKey else { return }
                measurement = result
            }
        }
    }

    private func updateHighlightCache() {
        let key = highlightKey
        guard key != cacheKey else { return }

        // Skip only truly pathological sizes — everything else attempts
        // highlighting and pops in when ready.
        guard data.code.count <= Self.maxHighlightChars else { return }

        guard highlightr != nil else { return }

        let codeSnapshot = data.code
        let language = data.language?.lowercased()
        let theme = themeName

        requestSeq &+= 1
        let mySeq = requestSeq

        Self.highlightQueue.async {
            guard let highlightr = highlightr else { return }
            highlightr.setTheme(to: theme)
            guard let nsAttr = highlightr.highlight(codeSnapshot, as: language) else { return }

            // Attribute diet, same as the measurement path.
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
        // Segmented blocks copy the *whole* group, not the local slice —
        // the user sees "one code fence" visually, so the copy button on
        // the first segment must mirror that intent.
        let toCopy = data.segment?.fullCode ?? data.code
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(toCopy, forType: .string)

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

// MARK: - Scroll forwarding

/// `NSScrollView` that handles horizontal wheel events itself but forwards
/// vertical-dominant events up the responder chain. Without this, the outer
/// SwiftUI `ScrollView` can't receive scroll gestures that start over a
/// large code block — AppKit's default behavior lets the inner scroll view
/// swallow every wheel event, even when it has no vertical content to scroll.
private final class HorizontalOnlyScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) < abs(event.scrollingDeltaY) {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

// MARK: - NSTextView wrapper for large code blocks

/// AppKit-backed code renderer for large blocks. Previously bridged its
/// computed height back to SwiftUI via `@Binding`; now consumes a
/// parent-supplied fixed frame and never mutates height after paint.
///
/// Measurement happens off-main (see `CodeBlockMeasurement`) using a
/// detached TextKit stack built by `CodeBlockLayoutConfig`. This view
/// configures its own container identically so the measured height and
/// the rendered height agree by construction.
private struct CodeTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    /// Highlighted result from the measurement cache, or `nil` for blocks
    /// above the highlight ceiling (rendered as plain monospaced).
    let highlighted: AttributedString?

    final class Coordinator {
        var lastTextHash: Int = 0
        var lastFont: NSFont?
        var lastHighlightHash: Int = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = HorizontalOnlyScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        // Prevent AppKit bounce from consuming vertical wheel events
        scrollView.verticalScrollElasticity = .none

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = font
        textView.textColor = .textColor

        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = .zero
        textView.autoresizingMask = [.width]

        if let container = textView.textContainer {
            CodeBlockLayoutConfig.apply(to: container)
        }

        scrollView.documentView = textView
        applyText(to: textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        applyText(to: textView, coordinator: context.coordinator)
    }

    /// Set text + font on the NSTextView. Deduped via the coordinator so
    /// SwiftUI's frequent `updateNSView` calls don't re-set multi-MB
    /// attributed strings on every pass.
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
            attributed = NSAttributedString(highlighted)
        } else {
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
