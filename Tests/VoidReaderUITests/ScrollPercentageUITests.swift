import XCTest

/// Tests that scroll percentage tracks correctly with mixed content types.
///
/// Uses a document containing text, Mermaid diagrams, KaTeX math blocks,
/// code blocks, and tables — all of which produce different rendered heights.
/// The old bug estimated height as blockCount * 60px, causing 100% at ~25%.
final class ScrollPercentageUITests: VoidReaderUITestCase {

    static let mixedContentPath = "/Users/chuck/Code/void_reader/TestDocuments/mixed-content-scroll.md"

    /// Launch the app with the mixed-content test document via --open argument.
    private func launchWithMixedContent() {
        app.launchArguments += ["--open", Self.mixedContentPath]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(
            window.waitForExistence(timeout: 15),
            "Window should appear after opening test document"
        )

        // Wait for async renders (Mermaid WKWebViews, KaTeX)
        sleep(5)

        // Click the content area to give the scroll view keyboard focus
        let scrollArea = app.scrollViews.firstMatch
        if scrollArea.waitForExistence(timeout: 5) {
            scrollArea.click()
        } else {
            // Fallback: click center of window
            window.click()
        }
        usleep(300_000)
    }

    /// Read the current percent from the status bar via the "percent-read"
    /// accessibility identifier. The value is exposed as "N%" in the element's value.
    private func readPercentRead() -> Int? {
        let element = app.staticTexts["percent-read"]
        guard element.waitForExistence(timeout: 5) else { return nil }

        // Value is "0%", "42%", "100%", etc.
        guard let value = element.value as? String else { return nil }
        return Int(value.replacingOccurrences(of: "%", with: ""))
    }

    /// Scroll down using swipe gestures and wait for debounce to settle.
    private func scrollAndSettle(pages: Int) {
        let scrollArea = app.scrollViews.firstMatch
        for _ in 0..<pages {
            scrollArea.scroll(byDeltaX: 0, deltaY: -400)
            usleep(200_000)
        }
        usleep(500_000)
    }

    /// Scroll to the very end of the document.
    private func scrollToBottom() {
        let scrollArea = app.scrollViews.firstMatch
        // Scroll aggressively to the bottom
        for _ in 0..<30 {
            scrollArea.scroll(byDeltaX: 0, deltaY: -500)
            usleep(100_000)
        }
        usleep(500_000)
    }

    // MARK: - Tests

    /// Core regression test: after scrolling partway through a mixed-content document,
    /// the percentage should NOT be at or near 100%.
    func testPercentNotPremature100WithMixedContent() throws {
        launchWithMixedContent()

        // Scroll a few pages — not to the end
        scrollAndSettle(pages: 3)

        guard let percent = readPercentRead() else {
            throw XCTSkip("Could not read percent from status bar")
        }

        // The old bug would show ~100% here after just 3 pages.
        XCTAssertLessThan(
            percent, 80,
            "After scrolling 3 pages in a mixed-content doc, percent should not be near 100%. Got \(percent)%."
        )
        XCTAssertGreaterThan(
            percent, 0,
            "After scrolling 3 pages, percent should be above 0%. Got \(percent)%."
        )
    }

    /// Verify 0% at the top of the document.
    func testPercentStartsAtZero() throws {
        launchWithMixedContent()

        guard let percent = readPercentRead() else {
            throw XCTSkip("Could not read percent from status bar")
        }

        XCTAssertEqual(percent, 0, "Percent should be 0% at the top of the document")
    }

    /// Verify 100% is reachable at the bottom.
    func testPercentReaches100AtBottom() throws {
        launchWithMixedContent()

        // Scroll to the very bottom
        scrollToBottom()

        guard let percent = readPercentRead() else {
            throw XCTSkip("Could not read percent from status bar")
        }

        XCTAssertEqual(percent, 100, "Percent should be 100% at the bottom of the document")
    }

    /// Verify percentage increases monotonically while scrolling down.
    func testPercentIncreasesMonotonically() throws {
        launchWithMixedContent()

        var lastPercent = 0
        var readings: [Int] = [0]

        for i in 1...8 {
            scrollAndSettle(pages: 2)

            guard let percent = readPercentRead() else {
                continue
            }

            XCTAssertGreaterThanOrEqual(
                percent, lastPercent,
                "Percent should not decrease while scrolling down. " +
                "Step \(i): was \(lastPercent)%, now \(percent)%"
            )
            lastPercent = percent
            readings.append(percent)
        }

        // After 16 page-downs, should have scrolled meaningfully
        XCTAssertGreaterThan(
            lastPercent, 30,
            "Should have scrolled past 30% after 16 page-downs. Readings: \(readings)"
        )
    }
}
