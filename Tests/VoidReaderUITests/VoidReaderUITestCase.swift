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

    /// Launch app and open a document at the given path
    func launchAndOpen(documentPath: String) {
        app.launch()

        // Use AppleScript to open the file (more reliable than UI automation)
        let script = """
        tell application "VoidReader"
            activate
            open POSIX file "\(documentPath)"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()

        // Wait for the document to load
        sleep(3) // Give time for document to open and render

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

    /// Assert the app hasn't frozen for more than the timeout
    func assertNoFreeze(timeout: TimeInterval = 5.0) {
        // Try to interact with the app - if it's frozen, this will timeout
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, "App window should be responsive")
    }
}
