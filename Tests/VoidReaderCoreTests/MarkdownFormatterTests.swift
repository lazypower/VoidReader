import Testing
@testable import VoidReaderCore

/// Torture tests for the one subsystem that rewrites the user's file on save.
/// The overriding invariant: the formatter never edits fenced code content.
@Suite("Markdown Formatter Tests")
struct MarkdownFormatterTests {

    // MARK: - Fence protection (the §2.1 corruption bugs)

    @Test("List markers inside a fence are left alone")
    func fencedListMarkersUntouched() {
        let input = """
        Outside list:

        * one
        + two

        ```yaml
        items:
          * keep-me
          + keep-me-too
        ```
        """
        let result = MarkdownFormatter.format(input)
        // Outside the fence, `*`/`+` normalize to the default dash.
        #expect(result.contains("- one"))
        #expect(result.contains("- two"))
        // Inside the fence, YAML sequence markers must survive verbatim.
        #expect(result.contains("  * keep-me"))
        #expect(result.contains("  + keep-me-too"))
    }

    @Test("__init__ is preserved inside a fenced block")
    func fencedEmphasisUntouched() {
        let input = """
        Prose __bold__ here.

        ```python
        def __init__(self):
            self.__dict__ = {}
        ```
        """
        let result = MarkdownFormatter.format(input)
        // Prose bold normalizes underscore -> star (default emphasis style).
        #expect(result.contains("**bold**"))
        // Dunder identifiers inside the fence stay intact.
        #expect(result.contains("def __init__(self):"))
        #expect(result.contains("self.__dict__ = {}"))
        #expect(!result.contains("**init**"))
        #expect(!result.contains("**dict**"))
    }

    @Test("__init__ is preserved inside an inline code span")
    func inlineCodeEmphasisUntouched() {
        let input = "Call `__init__` and `__dict__` but __really__ mean it."
        let result = MarkdownFormatter.format(input)
        #expect(result.contains("`__init__`"))
        #expect(result.contains("`__dict__`"))
        // The genuine emphasis outside the code spans still normalizes.
        #expect(result.contains("**really**"))
    }

    @Test("Shell pipelines in a fence are not rewritten as a table")
    func fencedPipelinesNotTables() {
        let input = """
        ```bash
        ps aux | grep foo
        cat x | wc -l
        ```
        """
        let result = MarkdownFormatter.format(input)
        #expect(result.contains("ps aux | grep foo"))
        #expect(result.contains("cat x | wc -l"))
        // Must NOT have grown table pipe framing.
        #expect(!result.contains("| ps aux | grep foo |"))
    }

    @Test("Heading-shaped comments in a fence keep their punctuation")
    func fencedHeadingCommentsUntouched() {
        let input = """
        ```sh
        # TODO: fix this.
        # NOTE: keep the colon:
        ```
        """
        let result = MarkdownFormatter.format(input)
        #expect(result.contains("# TODO: fix this."))
        #expect(result.contains("# NOTE: keep the colon:"))
    }

    @Test("Blank-line runs inside a fence are preserved")
    func fencedBlankRunsPreserved() {
        let input = """
        ```

        line after two blanks


        line after three blanks
        ```
        """
        let result = MarkdownFormatter.format(input)
        // The deliberate blank runs inside the fence must survive collapsing.
        #expect(result.contains("\n\n\nline after three blanks"))
    }

    @Test("Unterminated fence protects to end of document")
    func unterminatedFenceProtects() {
        let input = """
        ```python
        x = 1
        * not a list marker
        """
        let result = MarkdownFormatter.format(input)
        #expect(result.contains("* not a list marker"))
        #expect(!result.contains("- not a list marker"))
    }

    // MARK: - Data-loss fixes

    @Test("Emoji table cells are not deleted when aligning")
    func emojiTableCellsPreserved() {
        let input = """
        | Name | Status |
        | --- | --- |
        | Cat | 🐱 |
        | Dog | 🐶 |
        """
        let result = MarkdownFormatter.format(input)
        #expect(result.contains("🐱"))
        #expect(result.contains("🐶"))
        // No replacement characters from a split surrogate pair.
        #expect(!result.contains("\u{FFFD}"))
    }

    @Test("CRLF hard line breaks survive whitespace trimming")
    func crlfHardBreakPreserved() {
        let input = "First line with break  \r\nSecond line\r\n"
        let result = MarkdownFormatter.format(input)
        // The two-space hard break survives together with the CRLF ending
        // (checked as the fused "\r\n" grapheme; a stripped break would read
        // "break\r\n" with no spaces).
        #expect(result.contains("break  \r\n"))
        #expect(!result.contains("break\r\n"))
        // And CRLF input is not given a spurious extra blank line at EOF.
        #expect(!result.hasSuffix("\n\n"))
    }

    // MARK: - Non-fenced behavior still works (regression guard)

    @Test("Outside fences, list markers still normalize")
    func unfencedListMarkersNormalize() {
        let result = MarkdownFormatter.format("* item\n+ item2")
        #expect(result.contains("- item"))
        #expect(result.contains("- item2"))
    }

    @Test("Outside fences, heading trailing punctuation is removed")
    func unfencedHeadingPunctuationRemoved() {
        let result = MarkdownFormatter.format("# Title:\n\nbody")
        #expect(result.contains("# Title\n"))
    }

    @Test("Outside fences, a real table still aligns")
    func unfencedTableAligns() {
        let input = "| a | b |\n| - | - |\n| longvalue | x |"
        let result = MarkdownFormatter.format(input)
        // Header cell 'a' padded to the width of 'longvalue'; 'b' padded to the
        // separator's minimum width of 3.
        #expect(result.contains("| a         | b   |"))
    }

    @Test("Formatting is idempotent on a document with fences")
    func idempotentWithFences() {
        let input = """
        # Heading

        Some __text__ with `code`.

        ```js
        const x = 1 | 2;
        ```

        | a | b |
        | - | - |
        | 1 | 2 |
        """
        let once = MarkdownFormatter.format(input)
        let twice = MarkdownFormatter.format(once)
        #expect(once == twice)
    }
}

/// Direct unit coverage for the fence authority the formatter now depends on.
@Suite("Fence Map Tests")
struct FenceMapTests {

    @Test("Marks fence lines and interior as protected")
    func protectsFencedRegion() {
        let lines = ["before", "```swift", "let x = 1", "```", "after"]
        let map = FenceMap(lines: lines)
        #expect(!map.isProtected(0))
        #expect(map.isProtected(1))
        #expect(map.isProtected(2))
        #expect(map.isProtected(3))
        #expect(!map.isProtected(4))
    }

    @Test("Unterminated fence protects through the last line")
    func protectsUnterminated() {
        let lines = ["```", "code", "more code"]
        let map = FenceMap(lines: lines)
        #expect(map.isProtected(0))
        #expect(map.isProtected(1))
        #expect(map.isProtected(2))
        #expect(map.regions.first?.unterminated == true)
    }

    @Test("Tilde fences are recognized")
    func recognizesTildeFences() {
        let lines = ["~~~", "raw", "~~~", "out"]
        let map = FenceMap(lines: lines)
        #expect(map.isProtected(1))
        #expect(!map.isProtected(3))
    }

    @Test("A shorter backtick run does not close a longer fence")
    func closingFenceMustMatchLength() {
        let lines = ["````", "``` still inside", "````", "out"]
        let map = FenceMap(lines: lines)
        #expect(map.isProtected(1))
        #expect(map.isProtected(2))
        #expect(!map.isProtected(3))
    }
}
