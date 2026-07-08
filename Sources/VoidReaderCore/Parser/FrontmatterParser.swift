import Foundation

/// Parsed YAML frontmatter from a markdown document.
public struct FrontmatterData: Identifiable {
    public let id = UUID()
    /// Key-value pairs in document order.
    public var fields: [(key: String, value: String)]

    public init(fields: [(key: String, value: String)]) {
        self.fields = fields
    }

    /// Look up a value by key (case-insensitive).
    public func value(for key: String) -> String? {
        fields.first { $0.key.lowercased() == key.lowercased() }?.value
    }
}

/// Extracts YAML frontmatter from the top of a markdown document.
public struct FrontmatterParser {

    /// The closing `---` must appear within this many lines of the opener. Real
    /// frontmatter is small; bounding the search stops a document that merely
    /// opens with a `---` thematic break (with another `---` far below) from
    /// having the whole region in between silently swallowed as frontmatter.
    private static let maxScanLines = 50

    /// Result of parsing: the frontmatter (if any) and the remaining body.
    public struct Result {
        public var frontmatter: FrontmatterData?
        public var body: String
    }

    /// Parse frontmatter from markdown text.
    ///
    /// Expects the document to start with `---` on the very first line (no
    /// leading blank lines or preamble), followed by simple `key: value` YAML
    /// lines, closed by another `---`. Everything after the closing fence is
    /// returned as the body.
    public static func parse(_ text: String) -> Result {
        // Cheap first-line check — scan only to the first line break instead of
        // copying and splitting the whole document, so the common (no-frontmatter)
        // case stays proportional to the first line rather than the file. Handles
        // LF/CRLF/CR via `.newlines`. This runs on every render.
        let firstLineEnd = text.rangeOfCharacter(from: .newlines)?.lowerBound ?? text.endIndex
        guard text[..<firstLineEnd].trimmingCharacters(in: .whitespaces) == "---" else {
            return Result(frontmatter: nil, body: text)
        }

        // Confirmed a frontmatter opener; split into lines to find the close.
        let lines = text.components(separatedBy: .newlines)

        var closingIndex: Int?
        let scanLimit = min(lines.count, maxScanLines + 1)
        for i in 1..<scanLimit {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closingIndex = i
                break
            }
        }

        guard let endIndex = closingIndex else {
            // No closing fence — treat entire document as body
            return Result(frontmatter: nil, body: text)
        }

        // Parse key: value pairs between the fences
        var fields: [(key: String, value: String)] = []
        for i in 1..<endIndex {
            let line = lines[i]
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colonIndex])
                .trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            fields.append((key: key, value: value))
        }

        guard !fields.isEmpty else {
            return Result(frontmatter: nil, body: text)
        }

        // Body is everything after the closing ---
        let bodyLines = Array(lines[(endIndex + 1)...])
        let body = bodyLines.joined(separator: "\n")

        return Result(
            frontmatter: FrontmatterData(fields: fields),
            body: body
        )
    }
}
