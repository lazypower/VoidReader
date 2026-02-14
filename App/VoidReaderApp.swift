import SwiftUI
import VoidReaderCore

@main
struct VoidReaderApp: App {
    @AppStorage("showStatusBar") private var showStatusBar = true

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            // View menu additions
            CommandGroup(after: .toolbar) {
                Toggle("Show Status Bar", isOn: $showStatusBar)
                    .keyboardShortcut("/", modifiers: [.command, .shift])
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
    }
}

// MARK: - Notifications for document commands

extension Notification.Name {
    static let printDocument = Notification.Name("printDocument")
    static let exportPDF = Notification.Name("exportPDF")
    static let shareDocument = Notification.Name("shareDocument")
    static let scrollToHeading = Notification.Name("scrollToHeading")
}
