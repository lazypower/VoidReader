import Foundation

/// Pure calculation for scroll percentage based on measured dimensions.
public enum ScrollPercentage {
    /// Calculate scroll progress as a percentage (0-100).
    ///
    /// - Parameters:
    ///   - offset: How far the content has scrolled (distance from content top to viewport top)
    ///   - contentHeight: Total height of the scrollable content
    ///   - visibleHeight: Height of the visible viewport
    /// - Returns: Integer percentage clamped to 0-100, or 0 if content fits in viewport
    public static func calculate(offset: CGFloat, contentHeight: CGFloat, visibleHeight: CGFloat) -> Int {
        let scrollableHeight = contentHeight - visibleHeight
        guard scrollableHeight > 0 else { return 0 }
        return Int(min(100, max(0, (offset / scrollableHeight) * 100)))
    }
}
