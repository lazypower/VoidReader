import AppKit
import Foundation

/// Single source of truth for the TextKit stack configuration used to
/// render and measure code blocks. Measurement happens off-main on a
/// detached stack; rendering happens on-main in `CodeTextView`'s live
/// `NSTextView`. If those two configurations drift — different
/// `lineFragmentPadding`, different `containerSize`, different wrap
/// behavior — the measured height will not equal the rendered height,
/// and the prefix-sum-based scroll percentage will drift.
///
/// All config lives here so "measured height" and "rendered height" are
/// defined in one place, by construction.
enum CodeBlockLayoutConfig {
    /// No padding around text within the container. Matches what
    /// `CodeTextView`'s NSTextView sets on its own container. Measured
    /// height must use the same value.
    static let lineFragmentPadding: CGFloat = 0

    /// Unbounded width so long lines pan horizontally rather than wrap.
    /// If we ever add a wrap mode, this becomes the viewport width and
    /// must be captured in the `MeasurementKey` so the cache invalidates
    /// on resize.
    static let containerWidth: CGFloat = .greatestFiniteMagnitude

    /// Unbounded height — TextKit grows the container to fit.
    static let containerHeight: CGFloat = .greatestFiniteMagnitude

    /// Build a detached TextKit stack suitable for off-main measurement.
    /// `NSTextStorage` / `NSLayoutManager` / `NSTextContainer` are all
    /// thread-safe to use off-main *as long as none is attached to a live
    /// `NSTextView`*. Returns all three so the caller can hold strong
    /// references for the duration of the measurement.
    static func makeDetachedStack(
        for attributed: NSAttributedString
    ) -> (NSTextStorage, NSLayoutManager, NSTextContainer) {
        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            size: NSSize(width: containerWidth, height: containerHeight)
        )
        container.lineFragmentPadding = lineFragmentPadding
        container.widthTracksTextView = false
        layoutManager.addTextContainer(container)
        return (storage, layoutManager, container)
    }

    /// Apply shared config to a live `NSTextView`'s container so render-time
    /// layout matches measurement-time layout. Call from `CodeTextView.makeNSView`.
    static func apply(to container: NSTextContainer) {
        container.lineFragmentPadding = lineFragmentPadding
        container.widthTracksTextView = false
        container.containerSize = NSSize(width: containerWidth, height: containerHeight)
    }

    /// Measure the laid-out height of an attributed string under the shared
    /// config. Safe to call off-main. Returns a `ceil`ed pixel height so
    /// integer row arithmetic stays exact.
    ///
    /// `NSTextStorage` must outlive the layout call: in TextKit the storage
    /// strongly holds its layout managers while `NSLayoutManager.textStorage`
    /// is weak, so dropping the storage reference immediately strips the
    /// layout manager's backing and `usedRect` returns zero.
    /// `withExtendedLifetime` makes that lifetime requirement explicit.
    static func measureHeight(of attributed: NSAttributedString) -> CGFloat {
        let (storage, layoutManager, container) = makeDetachedStack(for: attributed)
        return withExtendedLifetime(storage) {
            layoutManager.ensureLayout(for: container)
            return ceil(layoutManager.usedRect(for: container).height)
        }
    }
}
