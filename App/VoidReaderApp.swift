import SwiftUI
import VoidReaderCore

@main
struct VoidReaderApp: App {
    @AppStorage("showStatusBar") private var showStatusBar = true

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
        }
        .commands {
            // View menu additions
            CommandGroup(after: .toolbar) {
                Toggle("Show Status Bar", isOn: $showStatusBar)
                    .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }
    }
}
