import AppKit
import CryptoKit
import Foundation
import Highlightr
import SwiftUI
import VoidReaderCore

/// Content-addressable cache key for a measured code block. Combines a
/// stable content hash (SHA256 of the code's UTF-8 bytes) with the
/// presentation parameters that influence layout. Using SHA256 rather
/// than `Swift.String.hashValue` because:
///
/// 1. `hashValue` is process-randomized since Swift 4.2 — unstable across
///    runs, so not persistable later if we ever want that.
/// 2. `hashValue` is an `Int`. Collisions, while rare, would silently
///    alias two different code blocks to the same cache entry — wrong,
///    not just slow. SHA256 collisions are cryptographically unreachable.
///
/// Presentation fields that must participate in the key: font name,
/// font size, theme (dark vs light syntax colors), container width,
/// and line fragment padding. Container width is captured even though
/// it's always `.greatestFiniteMagnitude` today, so the moment we add
/// a wrap mode the cache invalidates automatically.
struct CodeBlockMeasurementKey: Hashable {
    let contentHash: SHA256.Digest
    let fontName: String
    let fontSize: CGFloat
    let themeName: String
    let containerWidth: CGFloat
    let lineFragmentPadding: CGFloat

    init(
        code: String,
        fontName: String,
        fontSize: CGFloat,
        themeName: String,
        containerWidth: CGFloat = CodeBlockLayoutConfig.containerWidth,
        lineFragmentPadding: CGFloat = CodeBlockLayoutConfig.lineFragmentPadding
    ) {
        self.contentHash = SHA256.hash(data: Data(code.utf8))
        self.fontName = fontName
        self.fontSize = fontSize
        self.themeName = themeName
        self.containerWidth = containerWidth
        self.lineFragmentPadding = lineFragmentPadding
    }
}

/// Outcome of measuring a block. `attributed` is the highlighted result
/// (ready to hand to `NSTextView`), or `nil` for blocks above the
/// highlight ceiling — in which case the renderer uses a plain
/// attributed string built from the raw code + font at render time.
/// `height` is always authoritative once this result exists.
struct CodeBlockMeasurementResult {
    let attributed: AttributedString?
    let height: CGFloat
}

/// Document-scoped, actor-isolated cache mapping measurement keys to
/// `(highlighted attributed string, laid-out height)` pairs. Owned by
/// `ContentView` for the lifetime of a document and cleared when the
/// document changes. Does not participate in `VoidReaderCore` — this is
/// a rendering-layer optimization tied to AppKit TextKit, fonts, and
/// themes, not domain logic.
actor CodeBlockMeasurementCache {
    private var entries: [CodeBlockMeasurementKey: CodeBlockMeasurementResult] = [:]

    func get(_ key: CodeBlockMeasurementKey) -> CodeBlockMeasurementResult? {
        entries[key]
    }

    func set(_ key: CodeBlockMeasurementKey, result: CodeBlockMeasurementResult) {
        entries[key] = result
    }

    func clear() {
        entries.removeAll()
    }

    /// Whether the cache already holds a result for this key. Cheap read
    /// used by the prefetch scheduler to skip work that's already done.
    func contains(_ key: CodeBlockMeasurementKey) -> Bool {
        entries[key] != nil
    }
}

// MARK: - SwiftUI Environment

/// Environment key for the document-scoped measurement cache. Using
/// `Environment` rather than direct parameter threading because the cache
/// is a document-lifetime singleton and would otherwise need to flow
/// through every intermediate view (`MarkdownReaderView`, `BlockView`,
/// `ChunkView`) just to reach `CodeBlockView`.
private struct CodeBlockMeasurementCacheKey: EnvironmentKey {
    static let defaultValue: CodeBlockMeasurementCache? = nil
}

extension EnvironmentValues {
    /// Document-scoped cache of `(attributed, height)` for code blocks.
    /// Set on the reader root via `.environment(\.codeBlockMeasurementCache, cache)`.
    /// `CodeBlockView` reads it at appear time to short-circuit measurement
    /// when the prefetch has already populated the entry.
    var codeBlockMeasurementCache: CodeBlockMeasurementCache? {
        get { self[CodeBlockMeasurementCacheKey.self] }
        set { self[CodeBlockMeasurementCacheKey.self] = newValue }
    }
}

/// Computes `(attributed, height)` for a single code block, off-main.
/// Thread affinity note: `Highlightr`'s `JSContext` is thread-pinned, so
/// all calls to the shared highlighter instance must run on the same
/// queue. This computer is designed to run exclusively on
/// `CodeBlockMeasurementScheduler.queue`.
enum CodeBlockMeasurement {
    /// Maximum code size for which we attempt syntax highlighting. Above
    /// this, the measurement still runs (we need the authoritative height)
    /// but the attributed result is `nil` — the renderer will produce a
    /// plain attributed string at render time. This matches
    /// `CodeBlockView.maxHighlightChars` and exists here so the measurer
    /// can make the decision without crossing back to the main actor.
    static let maxHighlightChars = 1_000_000

    static func measure(
        code: String,
        language: String?,
        font: NSFont,
        themeName: String,
        highlighter: Highlightr?
    ) -> CodeBlockMeasurementResult {
        // Above the highlight ceiling, we still measure height (the renderer
        // needs an authoritative frame) but skip building + caching the
        // AttributedString: CodeTextView's `highlighted: nil` path will build
        // a plain string at render time from the raw code, so caching it
        // here is duplicated memory on exactly the blocks where memory
        // matters most.
        let measuredFor: NSAttributedString
        let shouldCacheAttributed: Bool

        if code.count <= maxHighlightChars, let highlightr = highlighter {
            highlightr.setTheme(to: themeName)
            if let highlighted = highlightr.highlight(code, as: language?.lowercased()) {
                measuredFor = slim(highlighted, font: font)
            } else {
                measuredFor = plain(code, font: font)
            }
            shouldCacheAttributed = true
        } else {
            measuredFor = plain(code, font: font)
            shouldCacheAttributed = false
        }

        let height = CodeBlockLayoutConfig.measureHeight(of: measuredFor)
        let swiftAttr: AttributedString? = shouldCacheAttributed
            ? (try? AttributedString(measuredFor, including: AttributeScopes.AppKitAttributes.self))
            : nil
        return CodeBlockMeasurementResult(attributed: swiftAttr, height: height)
    }

    /// Attribute diet: keep `.foregroundColor` runs from the highlighter,
    /// strip everything else, apply `.font` as a single run across the
    /// whole string. This lets NSAttributedString coalesce adjacent
    /// same-color runs — a large memory win for token-dense code.
    private static func slim(_ source: NSAttributedString, font: NSFont) -> NSAttributedString {
        let slim = NSMutableAttributedString(string: source.string)
        let fullRange = NSRange(location: 0, length: source.length)
        source.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            if let color = value as? NSColor {
                slim.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
        slim.addAttribute(.font, value: font, range: fullRange)
        return slim
    }

    private static func plain(_ code: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(
            string: code,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.textColor
            ]
        )
    }
}

/// Prefetch scheduler. Dispatches measurements off-main with a bounded
/// concurrency window so opening a document with hundreds of code blocks
/// doesn't overwhelm the system. Work is enqueued in document order so
/// blocks near the top (most likely to be visible first) measure first.
///
/// ## Thread affinity
/// All measurement work runs on `queue`, a serial dispatch queue. This
/// is required because `Highlightr`'s `JSContext` is thread-pinned; every
/// call to the shared instance must funnel through one thread. Serial
/// execution also keeps measurement load bounded without an extra
/// semaphore.
enum CodeBlockMeasurementScheduler {
    /// Serial queue — required for `Highlightr`/`JSContext` thread affinity.
    /// See `CodeBlockView.highlightQueue` for the history; this replaces
    /// the per-view queue with a single shared one so prefetch and
    /// on-demand measurement don't fight.
    static let queue = DispatchQueue(
        label: "place.wabash.VoidReader.measurement",
        qos: .userInitiated
    )

    /// Shared highlighter instance. `nil` is tolerated — measurement falls
    /// back to plain text in that case.
    static let highlighter: Highlightr? = Highlightr()

    /// Enqueue a single measurement. If the key is already cached, the
    /// closure returns immediately without touching the queue. Otherwise
    /// the work lands on `queue` in FIFO order and publishes back on main.
    ///
    /// The result is written into `cache` and the `onComplete` callback
    /// is invoked on the main actor so callers can update `@State` /
    /// `@Published` without hopping themselves.
    static func enqueueIfNeeded(
        code: String,
        language: String?,
        fontName: String,
        fontSize: CGFloat,
        themeName: String,
        cache: CodeBlockMeasurementCache,
        onComplete: @escaping @MainActor (CodeBlockMeasurementKey, CodeBlockMeasurementResult) -> Void
    ) {
        let key = CodeBlockMeasurementKey(
            code: code,
            fontName: fontName,
            fontSize: fontSize,
            themeName: themeName
        )

        Task {
            // Fast path: already cached.
            if let existing = await cache.get(key) {
                await MainActor.run { onComplete(key, existing) }
                return
            }

            // Resolve NSFont inside the queue closure rather than capturing
            // it across the Sendable boundary — NSFont is not `Sendable`,
            // but (fontName, fontSize) are. Resolution is pure and produces
            // the same font every time.
            queue.async {
                let resolvedFont: NSFont = {
                    if !fontName.isEmpty, let f = NSFont(name: fontName, size: fontSize) {
                        return f
                    }
                    return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
                }()
                let result = CodeBlockMeasurement.measure(
                    code: code,
                    language: language,
                    font: resolvedFont,
                    themeName: themeName,
                    highlighter: highlighter
                )
                Task {
                    await cache.set(key, result: result)
                    await MainActor.run { onComplete(key, result) }
                }
            }
        }
    }
}
