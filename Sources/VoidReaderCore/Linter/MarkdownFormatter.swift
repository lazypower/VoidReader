import Foundation

/// Formats markdown text with normalization of markers and whitespace.
///
/// Every pass is *fence-aware*: lines inside a fenced code block (see
/// ``FenceMap``) are left byte-for-byte untouched. This is the one subsystem
/// that rewrites the user's file on save, so the invariant is simple and
/// absolute — **the formatter never edits fenced content.** Silent corruption
/// of a code block is far worse than a missed cosmetic fix outside one.
public struct MarkdownFormatter {

    /// Formats markdown text according to the given options.
    /// - Parameters:
    ///   - text: The markdown source text
    ///   - options: Formatting preferences
    /// - Returns: Formatted markdown text
    public static func format(_ text: String, options: FormatterOptions = FormatterOptions()) -> String {
        var result = text

        // Normalize list markers
        result = normalizeListMarkers(result, style: options.listMarker)

        // Normalize emphasis markers to preferred style
        result = normalizeEmphasisMarkers(result, style: options.emphasisMarker)

        // Remove trailing punctuation from headings
        result = removeTrailingPunctuationFromHeadings(result)

        // Trim trailing whitespace from each line
        if options.trimTrailingWhitespace {
            result = trimTrailingWhitespace(result)
        }

        // Collapse multiple blank lines
        if options.collapseBlankLines {
            result = collapseMultipleBlankLines(result)
        }

        // Ensure blank lines around code blocks
        result = ensureBlankLinesAroundCodeBlocks(result)

        // Ensure blank lines around headings
        result = ensureBlankLinesAroundHeadings(result)

        // Align table columns
        result = alignTableColumns(result)

        // Ensure trailing newline. Compare at the scalar level so a CRLF
        // document (which ends in a single "\r\n" grapheme, not "\n") is not
        // mistaken for lacking a terminator and given a spurious blank line.
        if options.ensureTrailingNewline && !result.isEmpty && result.unicodeScalars.last != "\n" {
            result += "\n"
        }

        return result
    }

    /// Checks if text would change after formatting.
    public static func wouldChange(_ text: String, options: FormatterOptions = FormatterOptions()) -> Bool {
        let formatted = format(text, options: options)
        return formatted != text
    }

    // MARK: - Private Helpers

    /// Normalizes unordered list markers to the specified style.
    private static func normalizeListMarkers(_ text: String, style: FormatterOptions.ListMarkerStyle) -> String {
        let targetMarker = style.rawValue
        var lines = text.components(separatedBy: "\n")
        let fence = FenceMap(lines: lines)

        for i in 0..<lines.count where !fence.isProtected(i) {
            let line = lines[i]

            // Match unordered list item: optional whitespace, marker (- * +), space
            // Must have a space after the marker to distinguish from horizontal rules
            if let range = line.range(of: #"^(\s*)[-*+](\s+)"#, options: .regularExpression) {
                let prefix = line[range]
                // Extract leading whitespace and trailing spaces
                if let markerMatch = prefix.range(of: #"[-*+]"#, options: .regularExpression) {
                    let leading = String(prefix[prefix.startIndex..<markerMatch.lowerBound])
                    let trailing = String(prefix[markerMatch.upperBound..<range.upperBound])
                    let rest = String(line[range.upperBound...])
                    lines[i] = leading + targetMarker + trailing + rest
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Normalizes emphasis markers to the specified style.
    ///
    /// Applied per line (emphasis never spans lines) and skips two kinds of
    /// verbatim content: fenced blocks (whole line) and inline code spans
    /// (segment). So `__init__` stays `__init__` both inside a ```python fence
    /// and inside an inline `` `__init__` `` span, instead of becoming `**init**`.
    private static func normalizeEmphasisMarkers(_ text: String, style: FormatterOptions.EmphasisMarkerStyle) -> String {
        var lines = text.components(separatedBy: "\n")
        let fence = FenceMap(lines: lines)

        // Precompile the two transforms once.
        let boldFrom: (pattern: String, template: String)
        let italicFrom: (pattern: String, template: String)
        if style == .underscore {
            boldFrom = (#"\*\*([^*]+)\*\*"#, "__$1__")
            italicFrom = (#"(?<!\*)\*(?!\*)([^*\n]+)(?<!\*)\*(?!\*)"#, "_$1_")
        } else {
            boldFrom = (#"__([^_]+)__"#, "**$1**")
            italicFrom = (#"(?<!_)_(?!_)([^_\n]+)(?<!_)_(?!_)"#, "*$1*")
        }
        let boldRegex = try? NSRegularExpression(pattern: boldFrom.pattern)
        let italicRegex = try? NSRegularExpression(pattern: italicFrom.pattern)

        func apply(_ fragment: String) -> String {
            var out = fragment
            if let boldRegex {
                out = boldRegex.stringByReplacingMatches(
                    in: out, range: NSRange(out.startIndex..., in: out),
                    withTemplate: boldFrom.template
                )
            }
            if let italicRegex {
                out = italicRegex.stringByReplacingMatches(
                    in: out, range: NSRange(out.startIndex..., in: out),
                    withTemplate: italicFrom.template
                )
            }
            return out
        }

        for i in 0..<lines.count where !fence.isProtected(i) {
            lines[i] = splitInlineCodeSpans(lines[i])
                .map { $0.isCode ? $0.text : apply($0.text) }
                .joined()
        }

        return lines.joined(separator: "\n")
    }

    /// Splits a single line into alternating non-code and inline-code-span
    /// segments. A code span opens on a run of N backticks and closes on the
    /// next run of exactly N backticks (CommonMark §6.1). An unterminated run
    /// is not a code span, so its remainder is returned as ordinary text.
    private static func splitInlineCodeSpans(_ line: String) -> [(text: String, isCode: Bool)] {
        var segments: [(String, Bool)] = []
        var current = ""
        var openRun = 0            // backtick-run length that opened the current span, 0 when outside
        var i = line.startIndex

        while i < line.endIndex {
            guard line[i] == "`" else {
                current.append(line[i])
                i = line.index(after: i)
                continue
            }

            var runLength = 0
            var j = i
            while j < line.endIndex && line[j] == "`" {
                runLength += 1
                j = line.index(after: j)
            }
            let backticks = String(repeating: "`", count: runLength)

            if openRun == 0 {
                // Opening a span: emit the preceding text as non-code.
                segments.append((current, false))
                current = backticks
                openRun = runLength
            } else if runLength == openRun {
                // Closing the span.
                current.append(backticks)
                segments.append((current, true))
                current = ""
                openRun = 0
            } else {
                // Backticks inside a span that don't match the fence length.
                current.append(backticks)
            }
            i = j
        }

        // Any leftover — including an unterminated opener — is ordinary text.
        segments.append((current, false))
        return segments
    }

    /// Removes trailing punctuation from headings (MD026).
    private static func removeTrailingPunctuationFromHeadings(_ text: String) -> String {
        let badPunctuation: Set<Character> = [".", ",", ";", ":", "!"]
        var lines = text.components(separatedBy: "\n")
        let fence = FenceMap(lines: lines)

        for i in 0..<lines.count where !fence.isProtected(i) {
            let line = lines[i]

            // Only ATX headings (`#`..`######` followed by a space) — never a
            // shell comment or a `#`-prefixed line inside a fence.
            guard isATXHeading(line) else { continue }

            var modified = line
            // Remove trailing punctuation (but preserve any trailing CR).
            let hadCR = modified.hasSuffix("\r")
            if hadCR { modified.removeLast() }
            while let last = modified.last, badPunctuation.contains(last) {
                modified.removeLast()
            }
            while modified.last == " " {
                modified.removeLast()
            }
            if hadCR { modified.append("\r") }
            lines[i] = modified
        }

        return lines.joined(separator: "\n")
    }

    /// Trims trailing whitespace from each line.
    /// Preserves intentional double-space line breaks — and a trailing carriage
    /// return, so CRLF documents keep both their line endings and their hard
    /// breaks.
    private static func trimTrailingWhitespace(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let fence = FenceMap(lines: lines)

        for i in 0..<lines.count where !fence.isProtected(i) {
            let raw = lines[i]

            // Peel off a trailing CR (CRLF line ending) and reattach it after,
            // so it is never counted as content whitespace.
            let hasCR = raw.hasSuffix("\r")
            var line = hasCR ? String(raw.dropLast()) : raw

            // Count trailing spaces/tabs.
            var trailingCount = 0
            for char in line.reversed() {
                if char == " " || char == "\t" {
                    trailingCount += 1
                } else {
                    break
                }
            }

            // Preserve exactly 2 trailing spaces (GFM hard line break).
            if trailingCount == 2 && !line.hasSuffix("\t") {
                lines[i] = hasCR ? line + "\r" : line
                continue
            }

            while let last = line.last, last == " " || last == "\t" {
                line.removeLast()
            }
            lines[i] = hasCR ? line + "\r" : line
        }

        return lines.joined(separator: "\n")
    }

    /// Collapses multiple consecutive blank lines to a single blank line —
    /// except inside fenced blocks, where deliberate blank-line runs are kept.
    private static func collapseMultipleBlankLines(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let fence = FenceMap(lines: lines)
        var result: [String] = []
        var previousWasBlank = false

        for (i, line) in lines.enumerated() {
            if fence.isProtected(i) {
                // Fenced content is emitted verbatim; a blank line here never
                // participates in collapsing on either side.
                result.append(line)
                previousWasBlank = false
                continue
            }

            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                if !previousWasBlank {
                    result.append(line)
                }
                previousWasBlank = true
            } else {
                result.append(line)
                previousWasBlank = false
            }
        }

        return result.joined(separator: "\n")
    }

    /// Ensures blank lines before and after fenced code blocks. Driven by the
    /// ``FenceMap`` so nested/mismatched fences are handled by one authority.
    private static func ensureBlankLinesAroundCodeBlocks(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let fence = FenceMap(lines: lines)
        guard !fence.regions.isEmpty else { return text }

        let openLines = Set(fence.regions.map { $0.open })
        let closeLines = Set(fence.regions.map { $0.close })

        var result: [String] = []
        for (i, line) in lines.enumerated() {
            // Blank line before an opening fence.
            if openLines.contains(i),
               let last = result.last,
               !last.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append("")
            }

            result.append(line)

            // Blank line after a closing fence.
            if closeLines.contains(i),
               i + 1 < lines.count,
               !lines[i + 1].trimmingCharacters(in: .whitespaces).isEmpty {
                result.append("")
            }
        }

        return result.joined(separator: "\n")
    }

    /// Ensures blank lines before and after ATX headings (skipping fenced content).
    private static func ensureBlankLinesAroundHeadings(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let fence = FenceMap(lines: lines)

        var result: [String] = []
        for (i, line) in lines.enumerated() {
            let isHeading = !fence.isProtected(i) && isATXHeading(line)

            if isHeading,
               let last = result.last,
               !last.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append("")
            }

            result.append(line)

            if isHeading,
               i + 1 < lines.count,
               !lines[i + 1].trimmingCharacters(in: .whitespaces).isEmpty {
                result.append("")
            }
        }

        return result.joined(separator: "\n")
    }

    /// Aligns table columns by padding cells to equal width — but only over runs
    /// of *non-fenced* lines, so shell pipelines like `ps aux | grep foo` inside
    /// a code block are never mistaken for table rows.
    private static func alignTableColumns(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        let fence = FenceMap(lines: lines)
        var i = 0

        while i < lines.count {
            if !fence.isProtected(i) && isTableRow(lines[i]) {
                let tableStart = i
                var tableEnd = i

                // Extend only across contiguous, non-fenced table rows.
                while tableEnd < lines.count && !fence.isProtected(tableEnd) && isTableRow(lines[tableEnd]) {
                    tableEnd += 1
                }

                // Process table if it has at least 2 rows (header + separator)
                if tableEnd - tableStart >= 2 {
                    let tableLines = Array(lines[tableStart..<tableEnd])
                    let alignedTable = alignTable(tableLines)
                    for j in 0..<alignedTable.count {
                        lines[tableStart + j] = alignedTable[j]
                    }
                }

                i = tableEnd
            } else {
                i += 1
            }
        }

        return lines.joined(separator: "\n")
    }

    /// True for an ATX heading line: up to three leading spaces, one to six
    /// `#`, then a space or end of line.
    private static func isATXHeading(_ line: String) -> Bool {
        line.range(of: #"^ {0,3}#{1,6}(\s|$)"#, options: .regularExpression) != nil
    }

    /// Checks if a line looks like a table row.
    private static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("|") && !trimmed.hasPrefix("```") && !trimmed.hasPrefix("~~~")
    }

    /// Aligns a table's columns.
    private static func alignTable(_ lines: [String]) -> [String] {
        // Parse cells from each row
        var rows: [[String]] = []
        var columnCount = 0

        for line in lines {
            let cells = parseTableCells(line)
            rows.append(cells)
            columnCount = max(columnCount, cells.count)
        }

        guard columnCount > 0 else { return lines }

        // Calculate max width for each column (in grapheme clusters).
        var columnWidths = [Int](repeating: 0, count: columnCount)
        for row in rows {
            for (col, cell) in row.enumerated() where col < columnCount {
                // For separator row, minimum width is 3 (---)
                let isSeparator = cell.trimmingCharacters(in: .whitespaces)
                    .allSatisfy { $0 == "-" || $0 == ":" }
                let minWidth = isSeparator ? 3 : cell.count
                columnWidths[col] = max(columnWidths[col], minWidth)
            }
        }

        // Rebuild rows with aligned columns
        var result: [String] = []
        for row in rows {
            var cells: [String] = []

            for col in 0..<columnCount {
                let cell = col < row.count ? row[col] : ""
                let width = columnWidths[col]

                // Check if this is the separator row (usually row index 1)
                let trimmed = cell.trimmingCharacters(in: .whitespaces)
                let isSeparator = !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" || $0 == ":" }

                if isSeparator {
                    // Preserve alignment indicators
                    let leftAlign = trimmed.hasPrefix(":")
                    let rightAlign = trimmed.hasSuffix(":")

                    var separator = String(repeating: "-", count: width)
                    if leftAlign && rightAlign {
                        separator = ":" + String(repeating: "-", count: width - 2) + ":"
                    } else if leftAlign {
                        separator = ":" + String(repeating: "-", count: width - 1)
                    } else if rightAlign {
                        separator = String(repeating: "-", count: width - 1) + ":"
                    }
                    cells.append(separator)
                } else {
                    // Pad by grapheme count, never by UTF-16 length — the old
                    // `padding(toLength:)` measured UTF-16 units against a
                    // grapheme width and could delete emoji cells or split a
                    // surrogate pair into U+FFFD.
                    let deficit = max(0, width - cell.count)
                    cells.append(cell + String(repeating: " ", count: deficit))
                }
            }

            result.append("| " + cells.joined(separator: " | ") + " |")
        }

        return result
    }

    /// Parses cells from a table row.
    private static func parseTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)

        // Remove leading/trailing pipes
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }

        // Split by pipe and trim each cell
        return trimmed.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }
}
