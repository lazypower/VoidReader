import Foundation

/// Answers the single question the string-processing layer kept getting wrong:
/// *"is this line inside a fenced code block?"*
///
/// Built once from an array of lines, it is the sole authority on fence
/// boundaries for the formatter. Before this existed, every formatter pass
/// re-derived fence state independently — or, more often, didn't, and happily
/// rewrote list markers, emphasis, and "tables" inside code fences. This is the
/// miniature seed of the fence/code-span authority the codebase wants; kept
/// deliberately small and line-oriented because that is all the formatter needs.
struct FenceMap {

    /// A contiguous fenced region expressed as line indices into the source
    /// array. `open` and `close` are the delimiter lines themselves; every line
    /// in `open...close` is protected. When a fence is never closed, `close`
    /// is the last line of the document and `unterminated` is true.
    struct Region {
        let open: Int
        let close: Int
        let unterminated: Bool
    }

    let regions: [Region]
    private let protectedLines: Set<Int>

    init(lines: [String]) {
        var regions: [Region] = []
        var protected: Set<Int> = []
        var i = 0

        while i < lines.count {
            guard let open = Self.fenceDelimiter(lines[i]) else {
                i += 1
                continue
            }

            let openLine = i
            var closeLine = lines.count - 1
            var terminated = false
            var j = i + 1

            while j < lines.count {
                // A closing fence uses the same character, is at least as long,
                // and carries no info string (CommonMark §4.5).
                if let close = Self.fenceDelimiter(lines[j]),
                   close.character == open.character,
                   close.length >= open.length,
                   close.info.isEmpty {
                    closeLine = j
                    terminated = true
                    break
                }
                j += 1
            }

            for k in openLine...closeLine { protected.insert(k) }
            regions.append(Region(open: openLine, close: closeLine, unterminated: !terminated))
            i = terminated ? closeLine + 1 : lines.count
        }

        self.regions = regions
        self.protectedLines = protected
    }

    /// True when the line at `index` is part of a fenced code block (including
    /// the opening and closing fence lines).
    func isProtected(_ index: Int) -> Bool {
        protectedLines.contains(index)
    }

    // MARK: - Fence delimiter parsing

    private struct Delimiter {
        let character: Character
        let length: Int
        let info: String
    }

    /// Parses a line as a fence delimiter (``` ``` ``` or `~~~`), tolerating up
    /// to a few leading spaces of indentation. Returns nil for non-fence lines.
    private static func fenceDelimiter(_ line: String) -> Delimiter? {
        let body = line.drop { $0 == " " }
        guard let marker = body.first, marker == "`" || marker == "~" else { return nil }

        var length = 0
        var idx = body.startIndex
        while idx < body.endIndex && body[idx] == marker {
            length += 1
            idx = body.index(after: idx)
        }
        guard length >= 3 else { return nil }

        // Trim newlines too so a CRLF closing fence ("```\r") is still recognised
        // as empty-info and closes the block.
        let info = body[idx...].trimmingCharacters(in: .whitespacesAndNewlines)
        return Delimiter(character: marker, length: length, info: info)
    }
}
