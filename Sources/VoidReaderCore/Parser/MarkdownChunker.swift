import Foundation
import Markdown

/// Finds safe chunk boundaries for progressive rendering of large markdown
/// documents. Ensures cuts land on top-level AST block boundaries so neither
/// the prefix nor the suffix is syntactically malformed.
///
/// ## Why
/// The previous implementation (`findFirstChunkEnd` in `ContentView`) cut at
/// any line boundary at ~20KB / ~500 lines. This broke documents where a
/// single top-level block (code fence, long list, blockquote, table) spanned
/// the boundary — e.g. a 100k-line code block was cut mid-fence, causing the
/// parser to see a partial opener in the first chunk and orphaned content in
/// the second. See `FINDINGS_large_doc_rendering.md` §B3 for the cascade.
///
/// ## Approach
/// Parse the full document once with `swift-markdown`. Walk top-level block
/// children in order; return the end-offset of the first block whose end
/// extends at or past `targetSize`. If no such block exists (e.g. the whole
/// document is one giant block), return `text.count` so the document is
/// rendered as a single chunk. Parsing is cheap (~4ms per MB) so the extra
/// pass before rendering is negligible.
public enum MarkdownChunker {

    /// Find a safe character offset to cut at for progressive rendering.
    /// Always lands on a top-level block boundary.
    ///
    /// - Parameters:
    ///   - text: Full markdown source.
    ///   - targetSize: Cut at or past this many characters. Default 20_000.
    /// - Returns: Character offset where the first chunk ends. Returns
    ///   `text.count` when the whole document should be rendered as one chunk
    ///   (tiny doc, or a single block that spans everything).
    public static func findFirstChunkEnd(in text: String, targetSize: Int = 20_000) -> Int {
        // Fast path: tiny docs don't need chunking.
        if text.count <= targetSize {
            return text.count
        }

        let document = Document(parsing: text)

        // Precompute line-start offsets so each SourceLocation → char offset
        // conversion is O(1) instead of O(n). One linear pass over the text.
        let lineStarts = computeLineStarts(in: text)

        for block in document.children {
            guard let range = block.range else { continue }
            let endOffset = offset(atEndOf: range, lineStarts: lineStarts, textCount: text.count)
            if endOffset >= targetSize {
                return endOffset
            }
        }

        // No block boundary exists past targetSize — either the whole
        // document is one block (e.g. 3MB code fence) or the last block
        // ended before targetSize. Render as a single chunk.
        return text.count
    }

    /// Returns an array where `lineStarts[i]` is the character offset of
    /// line `(i + 1)`'s first character. `lineStarts[0] == 0` always.
    private static func computeLineStarts(in text: String) -> [Int] {
        var offsets = [0]
        var index = 0
        for char in text {
            index += 1
            if char == "\n" {
                offsets.append(index)
            }
        }
        return offsets
    }

    /// Character offset just past the end of a block's range — i.e. the start
    /// of the line after the block. Column is ignored because we only cut at
    /// newline boundaries (which sidesteps UTF-8/UTF-16 column-vs-byte
    /// ambiguity when the source contains multi-byte characters).
    private static func offset(
        atEndOf range: SourceRange,
        lineStarts: [Int],
        textCount: Int
    ) -> Int {
        // `range.upperBound.line` is 1-indexed and points at the block's last
        // line. The start of the NEXT line is `lineStarts[upperBound.line]`
        // (lineStarts is 0-indexed; line N starts at lineStarts[N-1], so
        // line N+1 starts at lineStarts[N]).
        let nextLineIndex = range.upperBound.line
        if nextLineIndex < lineStarts.count {
            return lineStarts[nextLineIndex]
        }
        // Block ends at/after the last newline — cut at document end.
        return textCount
    }
}
