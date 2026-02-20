import XCTest

/// Tests for VoidReader UI.
///
/// These tests verify basic app functionality:
/// - App launches and creates documents
/// - Edit mode toggle works
/// - Scrolling works
/// - Search works
///
/// Note: Large document testing with specific files requires additional setup.
/// For now, tests use new empty documents.
///
/// Run with: `make test-ui` or `xcodebuild test -scheme VoidReader -only-testing:VoidReaderUITests`
final class LargeDocumentTests: VoidReaderUITestCase {

    /// Basic test that the app launches and we can create a new document
    func testAppLaunches() throws {
        app.launch()

        // Document-based apps may not show a window until we create a document
        app.typeKey("n", modifierFlags: .command)

        // Wait for a window to appear
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15), "App window should exist after creating new document")

        print("Windows: \(app.windows.count)")
        if window.exists {
            print("Window title: \(window.title)")
        }
    }

    /// Test that creating a new document works and debug logging captures it
    func testOpenLargeDocument() throws {
        launchWithNewDocument()

        // The window should exist
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, "Window should be visible")

        // The app should remain responsive
        assertNoFreeze()

        // Check debug log for startup
        if let log = readDebugLog() {
            print("=== Debug Log (last 1000 chars) ===")
            print(String(log.suffix(1000)))

            // Verify startup was logged
            XCTAssertTrue(
                log.contains("lifecycle") || log.contains("VoidReader"),
                "Debug log should contain startup info"
            )
        }
    }

    /// Test toggling edit mode
    func testEditModeLargeDocument() throws {
        launchWithNewDocument()

        // New documents start in edit mode, toggle to reader
        toggleEditMode()
        sleep(1)

        // Toggle back to edit mode
        toggleEditMode()
        sleep(1)

        // App should remain responsive
        assertNoFreeze()

        // Check debug log for editor events
        if let log = readDebugLog() {
            print("=== Debug Log (last 500 chars) ===")
            print(String(log.suffix(500)))
        }
    }

    /// Test scrolling behavior
    func testScrollLargeDocument() throws {
        launchWithNewDocument()

        // Type some content so we have something to scroll
        app.typeKey("a", modifierFlags: [])  // Just type a character

        // Try scrolling (even if nothing to scroll, should not crash)
        for _ in 1...3 {
            scrollDown(pages: 1)
            assertNoFreeze()
            usleep(100_000)
        }

        for _ in 1...3 {
            scrollUp(pages: 1)
            assertNoFreeze()
            usleep(100_000)
        }
    }

    /// Test search functionality
    func testSearchLargeDocument() throws {
        launchWithNewDocument()

        // Open find bar
        openFindBar()
        sleep(1)

        // Should be able to type in search field
        let searchField = app.textFields["search-field"]
        if searchField.waitForExistence(timeout: 5) {
            searchField.click()  // Focus the field first
            searchField.typeText("test")
        }

        // Close search
        app.typeKey(.escape, modifierFlags: [])

        // App should remain responsive
        assertNoFreeze()
    }

    /// Test rapid keyboard input (stress test)
    func testRapidScrolling() throws {
        launchWithNewDocument()

        // Send many page down events quickly
        for _ in 1...10 {
            app.typeKey(.pageDown, modifierFlags: [])
            usleep(50_000) // 50ms
        }

        sleep(1)

        // App should still be responsive
        assertNoFreeze()
    }

    /// Test that debug logging is capturing memory info
    func testMemoryDuringScroll() throws {
        launchWithNewDocument()

        // Do some scrolling
        for _ in 1...5 {
            app.typeKey(.pageDown, modifierFlags: [])
            usleep(100_000)
        }

        // Check memory in log
        if let log = readDebugLog() {
            let memoryLines = log.components(separatedBy: "\n")
                .filter { $0.contains("MB") }
            print("Memory logged: \(memoryLines.joined(separator: "\n"))")

            // Should have at least startup memory
            XCTAssertFalse(memoryLines.isEmpty, "Should have memory info in debug log")
        }

        assertNoFreeze()
    }
}
