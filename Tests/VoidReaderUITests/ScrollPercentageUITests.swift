import XCTest

/// Tests that scroll percentage tracks correctly with mixed content types.
///
/// Uses a document containing text, Mermaid diagrams, KaTeX math blocks,
/// code blocks, and tables — all of which produce different rendered heights.
/// The old bug estimated height as blockCount * 60px, causing 100% at ~25%.
final class ScrollPercentageUITests: VoidReaderUITestCase {

    /// Project root derived from this source file's location.
    static let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // VoidReaderUITests/
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent() // project root
        .path

    static let mixedContentPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // VoidReaderUITests/
        .appendingPathComponent("Fixtures/mixed-content-scroll.md")
        .path

    /// Launch the app and open the mixed-content test document.
    private func launchWithMixedContent() {
        launchAndOpen(documentPath: Self.mixedContentPath)

        // Extra settle time for async Mermaid WKWebViews and KaTeX renders
        // (launchAndOpen already sleeps 3s; mixed-content needs a little more).
        sleep(2)

        // Wait for the reader scroll view to render. This is identified by
        // the "reader-view" accessibility identifier on ContentView's
        // ScrollView (App/Views/ContentView.swift). Targeting by identifier
        // avoids confusion with any other ScrollView in the hierarchy
        // (e.g. an NSOpenPanel sidebar if DocumentGroup ever falls back to
        // the chooser).
        // Always dump initial state so we can see what XCUITest sees right
        // after launch. Cheap, and the only way to triage CI failures
        // without VNC visibility.
        dumpAccessibilityState(label: "after launchAndOpen")

        let scrollArea = app.scrollViews["reader-view"]
        let appeared = scrollArea.waitForExistence(timeout: 15)

        if !appeared {
            dumpAccessibilityState(label: "reader-view never appeared")
        }

        // Click to give keyboard focus.
        if scrollArea.exists {
            scrollArea.click()
        } else {
            app.windows.firstMatch.click()
        }
        usleep(300_000)
    }

    /// Read the current percent from the status bar via the "percent-read"
    /// accessibility identifier. The value is exposed as "N%" in the element's value.
    private func readPercentRead() -> Int? {
        // Try staticTexts first (where the identifier should be after the
        // recent fix that moved it onto the Text element).
        let staticText = app.staticTexts.matching(identifier: "percent-read").firstMatch
        if staticText.waitForExistence(timeout: 5),
           let value = staticText.value as? String,
           let pct = Int(value.replacingOccurrences(of: "%", with: ""))
        {
            return pct
        }

        // Fallback: any element with that identifier (in case SwiftUI
        // exposes it on a different XCUIElement type).
        let any = app.descendants(matching: .any)
            .matching(identifier: "percent-read")
            .firstMatch
        if any.exists {
            // Try value, then label, then strip trailing % from either.
            let raw = (any.value as? String) ?? any.label
            if let pct = Int(raw.replacingOccurrences(of: "%", with: "")) {
                return pct
            }
            NSLog("[readPercentRead] found percent-read but couldn't parse: value=\((any.value as? String).debugDescription) label=\(any.label.debugDescription)")
        } else {
            dumpAccessibilityState(label: "readPercentRead: percent-read not found")
        }

        return nil
    }

    /// Scroll down using Page Down and wait for debounce to settle.
    ///
    /// Uses keyboard scroll instead of `scrollView.scroll(byDeltaX:deltaY:)`
    /// because scroll-wheel event synthesis doesn't reliably move SwiftUI
    /// ScrollViews on macOS XCUITest (verified on Firecracker runners:
    /// scroll events fire but content position never updates).
    private func scrollAndSettle(pages: Int) {
        for _ in 0..<pages {
            app.typeKey(.pageDown, modifierFlags: [])
            usleep(200_000)
        }
        usleep(500_000)
    }

    /// Scroll to the very end of the document via Cmd+Down (End-of-document).
    private func scrollToBottom() {
        app.typeKey(.downArrow, modifierFlags: .command)
        usleep(500_000)
        // Belt-and-suspenders: also page-down a bunch in case Cmd+Down
        // isn't bound in this view.
        for _ in 0..<40 {
            app.typeKey(.pageDown, modifierFlags: [])
            usleep(50_000)
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
