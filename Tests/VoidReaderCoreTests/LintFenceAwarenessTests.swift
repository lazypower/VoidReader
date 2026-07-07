import Testing
@testable import VoidReaderCore

/// MD009/MD012 used to be the only fence-blind lint rules, flagging trailing
/// whitespace and blank-line runs inside code fences where they are intentional.
@Suite("Lint fence awareness")
struct LintFenceAwarenessTests {

    @Test("MD009 ignores trailing whitespace inside a fence but not in prose")
    func md009SkipsFences() {
        let trail = "   " // 3 trailing spaces (past the 2-space hard-break exception)
        let source = "prose" + trail + "\n\n```\ncode" + trail + "\n```\n"
        let warnings = MD009TrailingWhitespace().check(
            document: MarkdownParser.parse(source), source: source
        )
        #expect(warnings.contains { $0.line == 1 })   // prose line flagged
        #expect(!warnings.contains { $0.line == 4 })  // fenced code line ignored
    }

    @Test("MD012 ignores blank-line runs inside a fence but not in prose")
    func md012SkipsFences() {
        let fenced = "```\ncode\n\n\nmore\n```\n" // two blank lines inside the fence
        let inFence = MD012MultipleBlankLines().check(
            document: MarkdownParser.parse(fenced), source: fenced
        )
        #expect(inFence.isEmpty)

        let prose = "para\n\n\nmore\n" // two blank lines in prose
        let inProse = MD012MultipleBlankLines().check(
            document: MarkdownParser.parse(prose), source: prose
        )
        #expect(!inProse.isEmpty)
    }
}
