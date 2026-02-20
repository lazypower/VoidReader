import Foundation

/// Parses inline math expressions ($...$) from text.
/// Does NOT match block math ($$...$$) or escaped dollars (\$).
public struct InlineMathParser {

    /// Represents a found inline math expression
    public struct Match {
        /// The LaTeX content (without the $ delimiters)
        public let latex: String
        /// The range of the full match (including $ delimiters) in the source
        public let range: Range<String.Index>
    }

    // Cached regex for performance - compiled once, reused
    private static let mathRegex: NSRegularExpression? = {
        // Pattern explanation:
        // (?<!\\)     - Negative lookbehind: not preceded by backslash (escaped)
        // (?<!\$)     - Negative lookbehind: not preceded by $ (would be $$)
        // \$          - Literal opening $
        // (?!\$)      - Negative lookahead: not followed by $ (would be $$)
        // ([^$]+?)    - Capture group: one or more non-$ characters (non-greedy)
        // \$          - Literal closing $
        // (?!\$)      - Negative lookahead: closing $ not followed by $ (would be $$)
        //
        // This ensures we match $x$ but not $$x$$ or $$ or \$
        let pattern = #"(?<!\\)(?<!\$)\$(?!\$)([^$]+?)\$(?!\$)"#
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    /// Extracts all inline math expressions from text.
    ///
    /// Rules:
    /// - Matches $...$ (single dollar delimiters)
    /// - Does NOT match $$...$$ (block math)
    /// - Does NOT match \$ (escaped dollars)
    /// - Content between $ must be non-empty
    ///
    /// - Parameter text: The source text to parse
    /// - Returns: Array of matches with latex content and ranges
    public static func extract(from text: String) -> [Match] {
        // Fast path: if no $ in text, skip regex
        guard text.contains("$") else {
            return []
        }

        var matches: [Match] = []

        guard let regex = mathRegex else {
            return []
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let results = regex.matches(in: text, options: [], range: nsRange)

        for result in results {
            guard let fullRange = Range(result.range, in: text),
                  let contentRange = Range(result.range(at: 1), in: text) else {
                continue
            }

            let latex = String(text[contentRange])

            // Additional safety check: ensure we're not part of a $$ sequence
            // Check character before our match (if exists)
            if fullRange.lowerBound > text.startIndex {
                let beforeIndex = text.index(before: fullRange.lowerBound)
                if text[beforeIndex] == "$" {
                    continue  // Skip - this is part of $$
                }
            }

            // Check character after our match (if exists)
            if fullRange.upperBound < text.endIndex {
                if text[fullRange.upperBound] == "$" {
                    continue  // Skip - this is part of $$
                }
            }

            matches.append(Match(latex: latex, range: fullRange))
        }

        return matches
    }
}
