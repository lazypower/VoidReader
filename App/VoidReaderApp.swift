import SwiftUI
import VoidReaderCore

@main
struct VoidReaderApp: App {
    @AppStorage("showStatusBar") private var showStatusBar = true
    @AppStorage("formatOnSave") private var formatOnSave = false

    init() {
        // Initialize debug logging on startup
        DebugLog.logStartup()

        // Handle --open argument for XCUITest
        handleOpenArgument()
    }

    /// Open a document path passed via the `--open` argument (for UI testing) or the
    /// `VOID_READER_OPEN` environment variable (for `make profile` / xctrace).
    ///
    /// Why env var alongside argv: when the path is in argv, AppKit/LaunchServices sees
    /// the file path and triggers an `application:openFiles:` event, which LaunchServices
    /// routes to a registered handler for the bundle ID — spawning a *second* process
    /// that opens the same document. Two processes, two windows, broken xctrace lifetime.
    /// Env vars aren't visible to LaunchServices' file-routing, so this stays single-process.
    private func handleOpenArgument() {
        let args = CommandLine.arguments
        var resolvedPath: String?

        if let openIndex = args.firstIndex(of: "--open"),
           openIndex + 1 < args.count {
            resolvedPath = args[openIndex + 1]
        } else if let envPath = ProcessInfo.processInfo.environment["VOID_READER_OPEN"],
                  !envPath.isEmpty {
            resolvedPath = envPath
        }

        if let path = resolvedPath {
            let url = URL(fileURLWithPath: path)
            DebugLog.info(.lifecycle, "Opening document from argument: \(path)")

            // Open after a short delay to let the app finish launching
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSDocumentController.shared.openDocument(
                    withContentsOf: url,
                    display: true
                ) { _, _, error in
                    if let error = error {
                        DebugLog.error(.lifecycle, "Failed to open: \(error.localizedDescription)")
                        return
                    }
                    // DocumentGroup auto-spawns an Untitled (or open-dialog) window at
                    // launch when no document is provided. Without --open this is fine,
                    // but with --open we now have two windows in the same process — the
                    // requested doc plus a blank Untitled. That keeps the process alive
                    // until both close, which breaks `make profile` (xctrace waits on
                    // process exit) and confused UI test cleanup. Close any docs without
                    // a fileURL — they're the auto-spawned blanks.
                    for doc in NSDocumentController.shared.documents where doc.fileURL == nil {
                        doc.close()
                    }
                }
            }
        }
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            // Edit menu - Format Document
            CommandGroup(after: .pasteboard) {
                Divider()

                Button("Format Document") {
                    NotificationCenter.default.post(name: .formatDocument, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            // View menu additions
            CommandGroup(after: .toolbar) {
                Toggle("Show Status Bar", isOn: $showStatusBar)
                    .keyboardShortcut("/", modifiers: [.command, .shift])

                Divider()

                Button("Open Themes Folder...") {
                    ThemeRegistry.shared.openThemesDirectory()
                }

                Button("Reload Themes") {
                    ThemeRegistry.shared.reloadUserThemes()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift, .option])
            }

            // File menu - Save with optional format
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    if formatOnSave {
                        NotificationCenter.default.post(name: .formatDocument, object: nil)
                    }
                    // Trigger standard save via responder chain
                    NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Reload from Disk") {
                    NotificationCenter.default.post(name: .reloadFromDisk, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            // File menu - Print (replace default)
            CommandGroup(replacing: .printItem) {
                Button("Print...") {
                    NotificationCenter.default.post(name: .printDocument, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }

            // File menu - Export as PDF
            CommandGroup(after: .importExport) {
                Button("Export as PDF...") {
                    NotificationCenter.default.post(name: .exportPDF, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Share...") {
                    NotificationCenter.default.post(name: .shareDocument, object: nil)
                }
            }
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Notifications for document commands

extension Notification.Name {
    static let printDocument = Notification.Name("printDocument")
    static let exportPDF = Notification.Name("exportPDF")
    static let shareDocument = Notification.Name("shareDocument")
    static let scrollToHeading = Notification.Name("scrollToHeading")
    static let formatDocument = Notification.Name("formatDocument")
    static let reloadFromDisk = Notification.Name("reloadFromDisk")
}
