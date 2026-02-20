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

    /// Open a document path passed via --open argument (for UI testing)
    private func handleOpenArgument() {
        let args = CommandLine.arguments
        if let openIndex = args.firstIndex(of: "--open"),
           openIndex + 1 < args.count {
            let path = args[openIndex + 1]
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
}
