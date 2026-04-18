import XCTest

/// Torture tests for scroll performance on extreme documents.
///
/// These tests open documents with 100K-line code blocks and 50K-row tables,
/// scroll aggressively, and assert that frame drops stay within acceptable limits.
///
/// The app exposes frame drop stats via a hidden accessibility element ("frame-drop-stats")
/// backed by FrameDropMonitor (CADisplayLink-based frame drop detection).
///
/// Run with: `make test-ui` or target `ScrollPerformanceTests` specifically.
final class ScrollPerformanceTests: VoidReaderUITestCase {

    /// Maximum acceptable dropped frames during a scroll test.
    /// A dropped frame = main thread blocked > 1.5x expected frame interval.
    /// On a 60fps display, that's >25ms of main-thread stall.
    ///
    /// Calibrated from debug build baseline:
    ///   Code block (butter-smooth): ~42 drops / 763 frames (~5.5%)
    ///   Table (needs work):         ~378 drops / 814 frames (~46%)
    /// Threshold set at ~2x the smooth baseline to absorb debug/CI variance.
    static let maxDroppedFrames = 100

    /// Number of page-down events per scroll burst.
    static let scrollPages = 20

    /// Project root derived from this source file's location.
    static let projectRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // VoidReaderUITests/
        .deletingLastPathComponent() // Tests/
        .deletingLastPathComponent() // project root
        .path

    /// Path to 100K-line code block test file.
    static let codeBlockPath = "\(projectRoot)/TestDocuments/torture_100k_code.md"

    /// Path to 50K-row table test file.
    static let tablePath = "\(projectRoot)/TestDocuments/torture_50k_table.md"

    // MARK: - Helpers

    /// Launch the app with a torture test document via --open argument.
    private func launchWithDocument(_ path: String, settleTime: UInt32 = 5) {
        app.launchArguments += ["--open", path]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(
            window.waitForExistence(timeout: 30),
            "Window should appear after opening test document"
        )

        // Wait for async rendering to complete
        sleep(settleTime)

        // Click content area to give scroll view keyboard focus
        let scrollArea = app.scrollViews.firstMatch
        if scrollArea.waitForExistence(timeout: 5) {
            scrollArea.click()
        } else {
            window.click()
        }
        usleep(300_000)
    }

    /// Read the frame drop stats from the hidden accessibility element.
    /// Returns (totalFrames, droppedFrames) or nil if not found.
    private func readFrameDropStats() -> (total: Int, dropped: Int)? {
        // Use firstMatch to avoid "multiple matching elements" when both
        // stringValue and accessibilityLabel match the same identifier.
        var statsElement = app.staticTexts.matching(identifier: "frame-drop-stats").firstMatch
        if !statsElement.waitForExistence(timeout: 3) {
            statsElement = app.otherElements.matching(identifier: "frame-drop-stats").firstMatch
        }
        if !statsElement.waitForExistence(timeout: 3) {
            // Debug: dump what's available
            print("DEBUG: Available static texts: \(app.staticTexts.allElementsBoundByAccessibilityElement.map { "\($0.identifier): \($0.label)" })")
            XCTFail("frame-drop-stats element not found")
            return nil
        }

        // The label format is "frames:N dropped:N"
        let label = statsElement.label
        guard let framesRange = label.range(of: "frames:"),
              let droppedRange = label.range(of: "dropped:") else {
            XCTFail("Unexpected frame-drop-stats format: \(label)")
            return nil
        }

        let framesStr = label[framesRange.upperBound..<droppedRange.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        let droppedStr = String(label[droppedRange.upperBound...])
            .trimmingCharacters(in: .whitespaces)

        guard let total = Int(framesStr), let dropped = Int(droppedStr) else {
            XCTFail("Could not parse frame-drop-stats: \(label)")
            return nil
        }

        return (total, dropped)
    }

    /// Scroll aggressively and measure frame drops as a delta from before/after.
    private func scrollAndMeasure(pages: Int, direction: ScrollDirection = .down) -> (total: Int, dropped: Int)? {
        // Read baseline stats before scroll
        guard let before = readFrameDropStats() else { return nil }

        // Perform aggressive scrolling
        for _ in 0..<pages {
            switch direction {
            case .down:
                app.typeKey(.pageDown, modifierFlags: [])
            case .up:
                app.typeKey(.pageUp, modifierFlags: [])
            }
            usleep(50_000) // 50ms between pages - aggressive but realistic
        }

        // Let rendering settle
        sleep(2)

        // Read stats after scroll
        guard let after = readFrameDropStats() else { return nil }

        let delta = (
            total: after.total - before.total,
            dropped: after.dropped - before.dropped
        )

        print("Scroll \(pages) pages \(direction): \(delta.total) frames, \(delta.dropped) dropped")
        return delta
    }

    private enum ScrollDirection: CustomStringConvertible {
        case down, up
        var description: String {
            switch self {
            case .down: return "down"
            case .up: return "up"
            }
        }
    }

    // MARK: - Tests

    /// 100K-line code block: scroll down aggressively, assert minimal frame drops.
    func testCodeBlock100KScrollPerformance() throws {
        launchWithDocument(Self.codeBlockPath)

        // Scroll down
        guard let downStats = scrollAndMeasure(pages: Self.scrollPages, direction: .down) else {
            return
        }

        XCTAssertGreaterThan(downStats.total, 0, "Should have rendered frames during scroll")
        XCTAssertLessThanOrEqual(
            downStats.dropped,
            Self.maxDroppedFrames,
            "100K code block scroll-down dropped \(downStats.dropped) frames (max \(Self.maxDroppedFrames))"
        )

        // Scroll back up
        guard let upStats = scrollAndMeasure(pages: Self.scrollPages, direction: .up) else {
            return
        }

        XCTAssertLessThanOrEqual(
            upStats.dropped,
            Self.maxDroppedFrames,
            "100K code block scroll-up dropped \(upStats.dropped) frames (max \(Self.maxDroppedFrames))"
        )

        assertNoFreeze()
    }

    /// 50K-row table: scroll down aggressively, assert minimal frame drops.
    func testTable50KScrollPerformance() throws {
        launchWithDocument(Self.tablePath, settleTime: 8)

        // Scroll down
        guard let downStats = scrollAndMeasure(pages: Self.scrollPages, direction: .down) else {
            return
        }

        XCTAssertGreaterThan(downStats.total, 0, "Should have rendered frames during scroll")
        XCTAssertLessThanOrEqual(
            downStats.dropped,
            Self.maxDroppedFrames,
            "50K table scroll-down dropped \(downStats.dropped) frames (max \(Self.maxDroppedFrames))"
        )

        // Scroll back up
        guard let upStats = scrollAndMeasure(pages: Self.scrollPages, direction: .up) else {
            return
        }

        XCTAssertLessThanOrEqual(
            upStats.dropped,
            Self.maxDroppedFrames,
            "50K table scroll-up dropped \(upStats.dropped) frames (max \(Self.maxDroppedFrames))"
        )

        assertNoFreeze()
    }

    /// 50K-row table: continuous trackpad-style scroll inside the table content.
    /// Simulates aggressive real trackpad scrolling with multiple bursts and directions.
    func testTable50KTrackpadScrollPerformance() throws {
        launchWithDocument(Self.tablePath, settleTime: 8)

        let scrollArea = app.scrollViews.firstMatch
        guard scrollArea.waitForExistence(timeout: 5) else {
            XCTFail("No scroll view found")
            return
        }
        scrollArea.click()
        usleep(300_000)

        guard let before = readFrameDropStats() else { return }

        // Burst 1: fast scroll down (simulates flick gesture)
        for _ in 0..<80 {
            scrollArea.scroll(byDeltaX: 0, deltaY: -15)
            usleep(8_000)  // ~120Hz event rate
        }
        usleep(500_000)  // brief pause

        // Burst 2: scroll back up aggressively
        for _ in 0..<80 {
            scrollArea.scroll(byDeltaX: 0, deltaY: 15)
            usleep(8_000)
        }
        usleep(500_000)

        // Burst 3: another fast scroll down
        for _ in 0..<80 {
            scrollArea.scroll(byDeltaX: 0, deltaY: -20)
            usleep(8_000)
        }

        sleep(2)

        guard let after = readFrameDropStats() else { return }
        let delta = (total: after.total - before.total, dropped: after.dropped - before.dropped)
        print("Trackpad scroll (aggressive): \(delta.total) frames, \(delta.dropped) dropped (\(delta.total > 0 ? (delta.dropped * 100 / delta.total) : 0)% drop rate)")

        XCTAssertGreaterThan(delta.total, 0, "Should have rendered frames")
        XCTAssertLessThanOrEqual(
            delta.dropped,
            Self.maxDroppedFrames,
            "Table trackpad scroll dropped \(delta.dropped) frames (max \(Self.maxDroppedFrames))"
        )
    }
}
