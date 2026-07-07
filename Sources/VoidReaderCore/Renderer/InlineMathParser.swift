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
        // Pattern (pandoc-style inline math), left to right:
        // (?<![\\$])   - opening $ not escaped and not the 2nd $ of a $$ pair
        // \$           - literal opening $
        // (?![$\s\d])  - opening delimiter must hug a non-space, non-digit char.
        //                The non-digit rule is what keeps "$5 and $10" (currency)
        //                from being read as math "$5 and $".
        // ([^$]+?)     - non-empty, non-greedy content (no $ inside)
        // (?<!\s)      - closing delimiter must hug a non-space char
        // \$           - literal closing $
        // (?![$\d])    - closing $ not part of $$ and not immediately before a digit
        let pattern = #"(?<![\\$])\$(?![$\s\d])([^$]+?)(?<!\s)\$(?![$\d])"#
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
            // The $$-adjacency the old code re-checked here is already guaranteed
            // by the (?<![\\$]) / (?![$\d]) lookarounds in the pattern, so the
            // post-hoc checks were dead code and have been removed.
            matches.append(Match(latex: latex, range: fullRange))
        }

        return matches
    }
}
