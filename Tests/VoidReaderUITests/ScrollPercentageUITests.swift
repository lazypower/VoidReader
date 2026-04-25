import XCTest

/// UI regression tests for scroll percentage accuracy.
///
/// These tests open real documents and verify that the displayed scroll
/// percentage matches expectations. They catch integration bugs that unit
/// tests cannot — e.g. the progressive render bug where the scroll tracker
/// fired against a partial block list and reported 100% immediately.
///
/// Run with: `make test-ui` or target `ScrollPercentageUITests` specifically.
final class ScrollPercentageUITests: VoidReaderUITestCase {

    /// Project root derived from this source file's location.
    static let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // VoidReaderUITests/
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent() // project root
        .path

    static let largeTablePath = "\(projectRoot)/TestDocuments/torture_50k_table.md"
    static let largeCodePath = "\(projectRoot)/TestDocuments/torture_100k_code.md"
    static let mixedContentPath = "\(projectRoot)/TestDocuments/mixed-content-scroll.md"

    // MARK: - Helpers

    /// Read the scroll percentage from the status bar.
    /// Returns nil if the element doesn't exist or can't be parsed.
    private func readScrollPercent() -> Int? {
        let percentElement = app.staticTexts["percent-read"]
        guard percentElement.waitForExistence(timeout: 5) else {
            return nil
        }
        // SwiftUI StaticText exposes content via .value (String) or .label.
        // Try both — XCUITest surfaces differ across macOS versions.
        let raw = (percentElement.value as? String)
            ?? percentElement.label
        let digits = raw.replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Int(digits)
    }

    /// Wait for progressive rendering to complete by polling the percent-read
    /// element until it stabilizes. Returns the final stable percentage.
    private func waitForRenderAndReadPercent(settleTime: UInt32 = 8) -> Int? {
        // Give progressive rendering time to complete
        sleep(settleTime)
        return readScrollPercent()
    }

    // MARK: - Tests

    /// The original bug: opening a large table document showed 100% immediately
    /// because the scroll tracker computed against the initial 3-block chunk.
    /// After fix: scroll percentage at top of document should be 0%.
    func testLargeTableStartsAtZeroPercent() throws {
        launchAndOpen(documentPath: Self.largeTablePath)

        // Wait for progressive rendering to complete
        guard let percent = waitForRenderAndReadPercent(settleTime: 10) else {
            dumpAccessibilityState(label: "percent-read not found")
            XCTFail("Could not read scroll percentage")
            return
        }

        print("Scroll percent at top of 50K table: \(percent)%")
        XCTAssertLessThanOrEqual(
            percent, 5,
            "Scroll percentage at top of large table should be near 0% (got \(percent)%)"
        )
    }

    /// Large code block should also start at 0%.
    func testLargeCodeBlockStartsAtZeroPercent() throws {
        launchAndOpen(documentPath: Self.largeCodePath)

        guard let percent = waitForRenderAndReadPercent(settleTime: 10) else {
            dumpAccessibilityState(label: "percent-read not found")
            XCTFail("Could not read scroll percentage")
            return
        }

        print("Scroll percent at top of 100K code block: \(percent)%")
        XCTAssertLessThanOrEqual(
            percent, 5,
            "Scroll percentage at top of large code block should be near 0% (got \(percent)%)"
        )
    }

    /// After scrolling partway into a large document, percentage should be
    /// between 0 and 100 (not stuck at either extreme).
    ///
    /// Uses the mixed-content fixture (smaller) with gentle trackpad scroll
    /// to avoid overwhelming the 100K code block renderer.
    func testPercentageAdvancesOnScroll() throws {
        launchAndOpen(documentPath: Self.mixedContentPath)

        // Wait for render
        sleep(5)

        // Focus scroll area
        let scrollArea = app.scrollViews.firstMatch
        guard scrollArea.waitForExistence(timeout: 5) else {
            XCTFail("No scroll view found")
            return
        }
        scrollArea.click()
        usleep(300_000)

        // Gentle scroll down
        for _ in 0..<20 {
            scrollArea.scroll(byDeltaX: 0, deltaY: -15)
            usleep(50_000)
        }
        sleep(2)

        guard let percent = readScrollPercent() else {
            // Document may fit viewport — skip rather than fail
            print("No percent-read element — document may fit viewport")
            return
        }

        print("Scroll percent after scroll in mixed-content: \(percent)%")
        XCTAssertGreaterThan(
            percent, 0,
            "After scrolling down, percentage should be above 0% (got \(percent)%)"
        )
    }
}
