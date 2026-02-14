import Foundation
import Markdown

/// Wrapper around swift-markdown for parsing markdown documents.
public struct MarkdownParser {

    /// Parse options for the markdown parser.
    public struct Options {
        /// Enable GitHub Flavored Markdown extensions (tables, strikethrough, etc.)
        public var enableGFM: Bool = true

        public init(enableGFM: Bool = true) {
            self.enableGFM = enableGFM
        }
    }

    /// Parses markdown text into a Document AST.
    /// - Parameters:
    ///   - text: The markdown source text
    ///   - options: Parsing options
    /// - Returns: Parsed Document
    public static func parse(_ text: String, options: Options = Options()) -> Document {
        // swift-markdown automatically handles GFM extensions
        return Document(parsing: text)
    }

    /// Extracts all headings from a document for outline/TOC generation.
    /// - Parameter document: The parsed document
    /// - Returns: Array of headings with their level and text
    public static func extractHeadings(from document: Document) -> [HeadingInfo] {
        var headings: [HeadingInfo] = []

        for child in document.children {
            if let heading = child as? Heading {
                let text = heading.plainText
                headings.append(HeadingInfo(level: heading.level, text: text))
            }
        }

        return headings
    }
}

/// Information about a heading for outline generation.
public struct HeadingInfo: Identifiable {
    public let id = UUID()
    public let level: Int
    public let text: String

    public init(level: Int, text: String) {
        self.level = level
        self.text = text
    }
}

// MARK: - Markup Extensions

extension Markup {
    /// Returns the plain text content of this markup element.
    var plainText: String {
        var result = ""
        for child in children {
            if let text = child as? Text {
                result += text.string
            } else {
                result += child.plainText
            }
        }
        return result
    }
}
