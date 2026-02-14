import SwiftUI
import VoidReaderCore

@main
struct VoidReaderApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
        }
        .commands {
            // Future: custom menu commands
        }
    }
}
