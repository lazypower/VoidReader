import XCTest
@testable import VoidReaderCore

final class InlineMathTests: XCTestCase {

    // MARK: - Basic Inline Math Detection

    func testSimpleInlineMath() {
        let result = InlineMathParser.extract(from: "The value is $x$ here")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].latex, "x")
    }

    func testMultipleInlineMath() {
        let result = InlineMathParser.extract(from: "Both $x$ and $y$ are variables")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].latex, "x")
        XCTAssertEqual(result[1].latex, "y")
    }

    func testInlineMathWithSuperscript() {
        let result = InlineMathParser.extract(from: "Formula: $x^2 + y^2 = z^2$")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].latex, "x^2 + y^2 = z^2")
    }

    func testInlineMathWithSubscript() {
        let result = InlineMathParser.extract(from: "The term $a_n$ represents...")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].latex, "a_n")
    }

    func testInlineMathWithGreekLetters() {
        let result = InlineMathParser.extract(from: "Where $\\alpha$ and $\\beta$ are constants")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].latex, "\\alpha")
        XCTAssertEqual(result[1].latex, "\\beta")
    }

    // MARK: - Block Math Should NOT Match

    func testBlockMathNotCaptured() {
        let result = InlineMathParser.extract(from: "$$x^2 + y^2$$")
        XCTAssertEqual(result.count, 0, "Block math $$ should not be captured as inline")
    }

    func testBlockMathWithNewlines() {
        let result = InlineMathParser.extract(from: """
            $$
            \\frac{a}{b}
            $$
            """)
        XCTAssertEqual(result.count, 0, "Multiline block math should not be captured")
    }

    func testMixedBlockAndInline() {
        let result = InlineMathParser.extract(from: """
            Inline $x$ here.

            $$
            y = mx + b
            $$

            And inline $z$ here.
            """)
        XCTAssertEqual(result.count, 2, "Should capture only inline math, not block")
        XCTAssertEqual(result[0].latex, "x")
        XCTAssertEqual(result[1].latex, "z")
    }

    func testBlockMathAdjacentToText() {
        let result = InlineMathParser.extract(from: "Text$$block$$more text")
        XCTAssertEqual(result.count, 0, "Adjacent $$ should be block math")
    }

    // MARK: - Escaped Dollars

    func testEscapedDollarNotCaptured() {
        let result = InlineMathParser.extract(from: "Price is \\$50 and \\$100")
        XCTAssertEqual(result.count, 0, "Escaped \\$ should not start math")
    }

    func testMixedEscapedAndReal() {
        let result = InlineMathParser.extract(from: "Cost \\$50 but math $x$ works")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].latex, "x")
    }

    // MARK: - Edge Cases

    func testEmptyDollars() {
        let result = InlineMathParser.extract(from: "Empty $$ is block")
        XCTAssertEqual(result.count, 0, "Empty $$ should not match as inline")
    }

    func testSingleDollarOnly() {
        let result = InlineMathParser.extract(from: "Just a $ sign alone")
        XCTAssertEqual(result.count, 0, "Single $ should not match")
    }

    func testDollarAtEndOfLine() {
        let result = InlineMathParser.extract(from: "Value is $x$")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].latex, "x")
    }

    func testDollarAtStartOfLine() {
        let result = InlineMathParser.extract(from: "$x$ is the value")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].latex, "x")
    }

    func testConsecutiveInlineMath() {
        let result = InlineMathParser.extract(from: "$a$$b$")  // This is $a$ followed by $b$
        // Actually this is ambiguous - could be $a$ + $b$ or block $$...
        // We should NOT match this to be safe
        XCTAssertEqual(result.count, 0, "Ambiguous $a$$b$ should not match")
    }

    func testInlineMathWithSpaces() {
        let result = InlineMathParser.extract(from: "$ x $ with spaces")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].latex, " x ")
    }

    func testNoMathAtAll() {
        let result = InlineMathParser.extract(from: "Just regular text here")
        XCTAssertEqual(result.count, 0)
    }

    func testComplexFormula() {
        let result = InlineMathParser.extract(from: "The formula $\\sum_{i=1}^{n} x_i$ sums values")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].latex, "\\sum_{i=1}^{n} x_i")
    }

    // MARK: - Range Tracking

    func testRangeTracking() {
        let text = "Here $x$ there"
        let result = InlineMathParser.extract(from: text)
        XCTAssertEqual(result.count, 1)

        // Verify the range points to "$x$" in the original string
        let matchedText = String(text[result[0].range])
        XCTAssertEqual(matchedText, "$x$")
    }
}
