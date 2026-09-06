import Foundation

/// One home for the size thresholds that gate rendering strategy, so the value
/// `50_000` — which meant three *unrelated* things across the view layer, plus a
/// `1_000_000` duplicated in two "these mirror each other" spots — has a single
/// named authority per concept and can't drift.
public enum RenderingThresholds {

    /// Documents below this many characters render synchronously; larger ones use
    /// the progressive chunked path.
    public static let syncRenderMaxChars = 50_000

    /// Above this many characters, the editor rehighlights only the visible
    /// region on edit/scroll instead of the whole document.
    public static let editorVisibleHighlightChars = 50_000

    /// Code blocks larger than this bypass the SwiftUI `Text` layout engine
    /// (which degrades on very large single strings) for a measured renderer.
    public static let codeBlockSwiftUITextMaxChars = 50_000

    /// Hard ceiling above which code is not syntax-highlighted at all — the
    /// highlighter's cost is superlinear, so past this we render plain text.
    public static let maxHighlightChars = 1_000_000

    /// Maximum size of one logical fenced code block that receives syntax
    /// coloring. Segmented blocks larger than this stay styled as monospaced
    /// code but skip token-level coloring; publishing thousands of highlight
    /// runs while the user scrolls causes a multi-second view-graph storm.
    public static let maxHighlightedLogicalCodeBlockChars = 200_000
}
