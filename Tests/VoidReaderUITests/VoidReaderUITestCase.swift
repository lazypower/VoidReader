import XCTest

/// Base class for VoidReader UI tests.
///
/// Provides common setup for launching the app with debug telemetry
/// and utilities for interacting with the UI.
class VoidReaderUITestCase: XCTestCase {

    var app: XCUIApplication!

    /// Path to the test document (50K lines)
    static let largeTestDocPath: String = {
        // Try bundle first (for when test resources are copied)
        if let bundlePath = Bundle(for: VoidReaderUITestCase.self).path(forResource: "large-test-50k", ofType: "md") {
            return bundlePath
        }
        // Fallback to repo path
        return "/Users/chuck/Code/void_reader/TestDocuments/large-test-50k.md"
    }()

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()

        // Suppress macOS window state restoration between test runs
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]

        // Enable debug telemetry
        app.launchEnvironment["VOID_READER_DEBUG"] = "1"

        // Optional: write logs to temp file for analysis
        let logPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("voidreader_uitest_\(name).log")
            .path
        app.launchEnvironment["VOID_READER_DEBUG_FILE"] = logPath
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Launch app and open a document at the given path.
    ///
    /// Passes the document path as a launch argument. DocumentGroup-based
    /// apps interpret file-path arguments at launch the same way as a
    /// Finder double-click — no AppleEvent involved. This avoids the race
    /// between `app.launch()` and a follow-up `open -a` we'd hit on
    /// Firecracker runners (the doc would never open, leaving only the
    /// default Untitled window).
    func launchAndOpen(documentPath: String) {
        app.launchArguments += [documentPath]
        app.launch()

        // Wait for the document to load
        sleep(3)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 30), "Window should exist after opening document")
    }

    /// Launch app with a new empty document
    func launchWithNewDocument() {
        app.launch()
        app.typeKey("n", modifierFlags: .command)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), "Window should exist after new document")
    }

    /// Open a file using the keyboard shortcut and file dialog
    func openFileViaDialog(path: String) {
        // Cmd+O to open file dialog
        app.typeKey("o", modifierFlags: .command)

        // Wait for dialog
        let dialog = app.sheets.firstMatch
        let dialogExists = dialog.waitForExistence(timeout: 5)

        if dialogExists {
            // Type the path (Cmd+Shift+G for Go to Folder)
            app.typeKey("g", modifierFlags: [.command, .shift])

            let goToSheet = app.sheets.element(boundBy: 1)
            if goToSheet.waitForExistence(timeout: 2) {
                goToSheet.textFields.firstMatch.typeText(path)
                app.typeKey(.enter, modifierFlags: [])
                sleep(1)
                app.typeKey(.enter, modifierFlags: [])
            }
        }
    }

    /// Scroll down by page
    func scrollDown(pages: Int = 1) {
        for _ in 0..<pages {
            app.typeKey(.pageDown, modifierFlags: [])
            usleep(100_000) // 100ms between scrolls
        }
    }

    /// Scroll up by page
    func scrollUp(pages: Int = 1) {
        for _ in 0..<pages {
            app.typeKey(.pageUp, modifierFlags: [])
            usleep(100_000)
        }
    }

    /// Toggle edit mode (Cmd+E)
    func toggleEditMode() {
        app.typeKey("e", modifierFlags: .command)
    }

    /// Open find bar (Cmd+F)
    func openFindBar() {
        app.typeKey("f", modifierFlags: .command)
    }

    /// Type search text and search
    func search(for text: String) {
        openFindBar()
        sleep(1)
        let searchField = app.textFields["search-field"]
        if searchField.waitForExistence(timeout: 2) {
            searchField.click()
            searchField.typeText(text)
        }
    }

    /// Read the debug log file contents
    func readDebugLog() -> String? {
        guard let logPath = app.launchEnvironment["VOID_READER_DEBUG_FILE"] else {
            return nil
        }
        return try? String(contentsOfFile: logPath, encoding: .utf8)
    }

    /// Dump the full XCUITest view of the app to NSLog. Call from any
    /// test diagnostic path — output lands in xcodebuild stderr, which
    /// CI captures and `tea actions runs logs` returns.
    ///
    /// Includes window titles + frames, the full element tree, and a
    /// flat list of every accessibility identifier present.
    func dumpAccessibilityState(label: String) {
        var report = "\n========== XCUITest dump: \(label) ==========\n"

        // Window summary
        let windowCount = app.windows.count
        report += "Windows: \(windowCount)\n"
        for i in 0..<windowCount {
            let w = app.windows.element(boundBy: i)
            report += "  [\(i)] title=\(w.title.debugDescription) frame=\(w.frame)\n"
        }

        // All identifiers present anywhere in the hierarchy
        let allElements = app.descendants(matching: .any).allElementsBoundByIndex
        let identifiers = allElements
            .map { $0.identifier }
            .filter { !$0.isEmpty }
        report += "\nIdentifiers present (\(identifiers.count)):\n"
        for id in Set(identifiers).sorted() {
            report += "  - \(id)\n"
        }

        // Full element tree (truncated if huge — 10K char cap)
        let tree = app.debugDescription
        let truncated = tree.count > 10_000
            ? String(tree.prefix(10_000)) + "\n  ... (truncated, full tree was \(tree.count) chars)"
            : tree
        report += "\nElement tree:\n\(truncated)\n"

        report += "========== end dump: \(label) ==========\n"
        NSLog("%@", report)
        // Also print to stdout so it's visible in xcodebuild output
        print(report)
    }

    /// Assert the app hasn't frozen for more than the timeout
    func assertNoFreeze(timeout: TimeInterval = 5.0) {
        // Try to interact with the app - if it's frozen, this will timeout
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, "App window should be responsive")
    }
}
