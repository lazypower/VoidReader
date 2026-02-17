import Foundation

/// Formats markdown text with normalization of markers and whitespace.
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

        // Ensure trailing newline
        if options.ensureTrailingNewline && !result.isEmpty && !result.hasSuffix("\n") {
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

        for i in 0..<lines.count {
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
    private static func normalizeEmphasisMarkers(_ text: String, style: FormatterOptions.EmphasisMarkerStyle) -> String {
        var result = text

        // Replace bold from opposite style
        if style == .underscore {
            // Convert **text** to __text__
            if let regex = try? NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result, options: [],
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "__$1__"
                )
            }
        } else {
            // Convert __text__ to **text**
            if let regex = try? NSRegularExpression(pattern: #"__([^_]+)__"#, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result, options: [],
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "**$1**"
                )
            }
        }

        // Replace italic from opposite style
        if style == .underscore {
            // Convert *text* to _text_ (but not **)
            if let regex = try? NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)([^*\n]+)(?<!\*)\*(?!\*)"#, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result, options: [],
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "_$1_"
                )
            }
        } else {
            // Convert _text_ to *text* (but not __)
            if let regex = try? NSRegularExpression(pattern: #"(?<!_)_(?!_)([^_\n]+)(?<!_)_(?!_)"#, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result, options: [],
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "*$1*"
                )
            }
        }

        return result
    }

    /// Removes trailing punctuation from headings (MD026).
    private static func removeTrailingPunctuationFromHeadings(_ text: String) -> String {
        let badPunctuation: Set<Character> = [".", ",", ";", ":", "!"]
        var lines = text.components(separatedBy: "\n")

        for i in 0..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect ATX heading
            if trimmed.hasPrefix("#") {
                var modified = line
                // Remove trailing punctuation (but preserve the line's trailing whitespace structure)
                while let last = modified.last, badPunctuation.contains(last) {
                    modified.removeLast()
                }
                // Also trim any trailing spaces that were before the punctuation
                while modified.last == " " {
                    modified.removeLast()
                }
                lines[i] = modified
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Trims trailing whitespace from each line.
    /// Preserves intentional double-space line breaks.
    private static func trimTrailingWhitespace(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")

        for i in 0..<lines.count {
            var line = lines[i]

            // Count trailing whitespace
            var trailingCount = 0
            for char in line.reversed() {
                if char.isWhitespace && char != "\n" {
                    trailingCount += 1
                } else {
                    break
                }
            }

            // Preserve exactly 2 trailing spaces (hard line break)
            if trailingCount == 2 {
                continue
            }

            // Remove all trailing whitespace
            while let last = line.last, last.isWhitespace && last != "\n" {
                line.removeLast()
            }
            lines[i] = line
        }

        return lines.joined(separator: "\n")
    }

    /// Collapses multiple consecutive blank lines to a single blank line.
    private static func collapseMultipleBlankLines(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var previousWasBlank = false

        for line in lines {
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

    /// Ensures blank lines before and after headings.
    private static func ensureBlankLinesAroundHeadings(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect ATX heading (# ... ######)
            if trimmed.hasPrefix("#") && trimmed.contains(" ") {
                // Ensure blank line before (if not at start and previous not blank)
                if i > 0 {
                    let prevLine = lines[i - 1].trimmingCharacters(in: .whitespaces)
                    if !prevLine.isEmpty {
                        lines.insert("", at: i)
                        i += 1
                    }
                }

                // Ensure blank line after (if not at end and next not blank)
                if i + 1 < lines.count {
                    let nextLine = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if !nextLine.isEmpty {
                        lines.insert("", at: i + 1)
                    }
                }
            }
            i += 1
        }

        return lines.joined(separator: "\n")
    }

    /// Ensures blank lines before and after fenced code blocks.
    private static func ensureBlankLinesAroundCodeBlocks(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect code fence (``` or ~~~)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                // Ensure blank line before (if not at start and previous line not blank)
                if i > 0 {
                    let prevLine = lines[i - 1].trimmingCharacters(in: .whitespaces)
                    if !prevLine.isEmpty {
                        lines.insert("", at: i)
                        i += 1
                    }
                }

                // Find closing fence
                let fenceChar = trimmed.hasPrefix("```") ? "```" : "~~~"
                var j = i + 1
                while j < lines.count {
                    let checkLine = lines[j].trimmingCharacters(in: .whitespaces)
                    if checkLine.hasPrefix(fenceChar) {
                        // Found closing fence, ensure blank line after
                        if j + 1 < lines.count {
                            let nextLine = lines[j + 1].trimmingCharacters(in: .whitespaces)
                            if !nextLine.isEmpty {
                                lines.insert("", at: j + 1)
                            }
                        }
                        i = j + 1
                        break
                    }
                    j += 1
                }
            }
            i += 1
        }

        return lines.joined(separator: "\n")
    }

    /// Aligns table columns by padding cells to equal width.
    private static func alignTableColumns(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            // Detect table start (line with | characters)
            if isTableRow(lines[i]) {
                let tableStart = i
                var tableEnd = i

                // Find extent of table
                while tableEnd < lines.count && isTableRow(lines[tableEnd]) {
                    tableEnd += 1
                }

                // Process table if it has at least 2 rows (header + separator)
                if tableEnd - tableStart >= 2 {
                    let tableLines = Array(lines[tableStart..<tableEnd])
                    let alignedTable = alignTable(tableLines)

                    // Replace table lines
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

        // Calculate max width for each column
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
                let isSeparator = trimmed.allSatisfy { $0 == "-" || $0 == ":" }

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
                    // Pad cell content
                    cells.append(cell.padding(toLength: width, withPad: " ", startingAt: 0))
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
