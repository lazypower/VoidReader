import Foundation
import Markdown
import SwiftUI

/// Renders markdown text to AttributedString for native display.
public struct MarkdownRenderer {

    /// Styling configuration for rendered markdown.
    public struct Style {
        // Base typography
        public var bodySize: CGFloat = 16
        public var bodyWeight: Font.Weight = .regular
        public var fontFamily: String? = nil  // nil = system font

        // Heading scale (relative to body size)
        public var h1Scale: CGFloat = 2.0
        public var h2Scale: CGFloat = 1.5
        public var h3Scale: CGFloat = 1.25
        public var h4Scale: CGFloat = 1.1
        public var h5Scale: CGFloat = 1.0
        public var h6Scale: CGFloat = 0.9

        // Code styling
        public var codeSize: CGFloat = 14
        public var codeFontFamily: String? = nil  // nil = system mono

        // Paragraph spacing
        public var paragraphSpacing: CGFloat = 12
        public var headingSpacing: CGFloat = 20

        // Theme colors (nil = use system semantic colors)
        public var textColor: Color? = nil          // nil → .primary
        public var secondaryColor: Color? = nil     // nil → .secondary
        public var linkColor: Color? = nil          // nil → Color.accentColor
        public var codeBackground: Color? = nil     // nil → quaternaryLabelColor
        public var mathColor: Color? = nil          // nil → purple accent for math
        public var headingColor: Color? = nil       // nil → textColor
        public var listMarkerColor: Color? = nil    // nil → secondaryColor
        public var blockquoteColor: Color? = nil    // nil → secondaryColor

        public init() {}

        /// Resolved text color (semantic or themed)
        public var resolvedTextColor: Color {
            textColor ?? .primary
        }

        /// Resolved secondary color (semantic or themed)
        public var resolvedSecondaryColor: Color {
            secondaryColor ?? .secondary
        }

        /// Resolved link color (semantic or themed)
        public var resolvedLinkColor: Color {
            linkColor ?? Color.accentColor
        }

        /// Resolved code background (semantic or themed)
        public var resolvedCodeBackground: Color {
            codeBackground ?? Color(nsColor: .quaternaryLabelColor).opacity(0.5)
        }

        /// Resolved math color (semantic or themed)
        public var resolvedMathColor: Color {
            mathColor ?? Color.purple
        }

        /// Resolved heading color (falls back to text color)
        public var resolvedHeadingColor: Color {
            headingColor ?? resolvedTextColor
        }

        /// Resolved list marker color (falls back to secondary color)
        public var resolvedListMarkerColor: Color {
            listMarkerColor ?? resolvedSecondaryColor
        }

        /// Resolved blockquote color (falls back to secondary color)
        public var resolvedBlockquoteColor: Color {
            blockquoteColor ?? resolvedSecondaryColor
        }

        /// Creates a font with the configured family
        public func makeFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            if let family = fontFamily {
                return .custom(family, size: size)
            }
            return .system(size: size, weight: weight)
        }

        /// Creates a code font with the configured family
        public func makeCodeFont(size: CGFloat) -> Font {
            if let family = codeFontFamily {
                return .custom(family, size: size)
            }
            return .system(size: size, design: .monospaced)
        }
    }

}

