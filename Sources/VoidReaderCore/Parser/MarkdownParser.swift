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
        // Track the slugs actually ASSIGNED (not just base counts) so a heading
        // whose natural slug equals an earlier dedup suffix — e.g. "Overview",
        // "Overview", "Overview 1" → overview, overview-1, overview-1-1 — still
        // gets a unique, reachable anchor. Otherwise every duplicate resolves to
        // the first match.
        var assigned: Set<String> = []

        for child in document.children {
            if let heading = child as? Heading {
                let text = heading.plainText
                let base = HeadingInfo.slug(from: text)
                var uniqueSlug = base
                var suffix = 1
                while assigned.contains(uniqueSlug) {
                    uniqueSlug = "\(base)-\(suffix)"
                    suffix += 1
                }
                assigned.insert(uniqueSlug)
                headings.append(HeadingInfo(level: heading.level, text: text, slug: uniqueSlug))
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

    /// GitHub-style anchor slug for in-document linking, unique within the
    /// document (duplicates carry a -1/-2 suffix assigned by `extractHeadings`).
    /// e.g. "My Section (v2)" → "my-section-v2".
    public let slug: String

    public init(level: Int, text: String, slug: String? = nil) {
        self.level = level
        self.text = text
        self.slug = slug ?? HeadingInfo.slug(from: text)
    }

    /// Generates a slug from arbitrary heading text (static version for link resolution).
    public static func slug(from text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
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
