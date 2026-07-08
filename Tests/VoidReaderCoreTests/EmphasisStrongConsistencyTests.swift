import Testing
@testable import VoidReaderCore

/// MD049 used to pool emphasis (*) and strong (**) markers into one check, so a
/// valid `_italic_` + `**bold**` document was flagged. markdownlint treats them
/// separately: MD049 (emphasis) and MD050 (strong).
@Suite("Emphasis/strong consistency (MD049/MD050)")
struct EmphasisStrongConsistencyTests {

    private func md049(_ src: String) -> [LintWarning] {
        MD049ConsistentEmphasis().check(document: MarkdownParser.parse(src), source: src)
    }
    private func md050(_ src: String) -> [LintWarning] {
        MD050ConsistentStrong().check(document: MarkdownParser.parse(src), source: src)
    }

    @Test("MD049 flags mixed emphasis but ignores strong markers")
    func md049EmphasisOnly() {
        #expect(!md049("*a* and _b_").isEmpty)  // mixed emphasis
        #expect(md049("*a* and **b**").isEmpty)  // strong ignored → emphasis all '*'
    }

    @Test("MD050 flags mixed strong but ignores emphasis markers")
    func md050StrongOnly() {
        #expect(!md050("**a** and __b__").isEmpty) // mixed strong
        #expect(md050("**a** and *b*").isEmpty)     // emphasis ignored → strong all '**'
    }

    @Test("_italic_ + **bold** is no longer a false positive")
    func noFalsePositiveAcrossKinds() {
        let src = "_italic_ and **bold**"
        #expect(md049(src).isEmpty)
        #expect(md050(src).isEmpty)
    }

    @Test("MD050 is registered in the linter's rule set")
    func md050Registered() {
        #expect(MarkdownLinter.allRules.contains { $0.id == "MD050" })
    }
}
