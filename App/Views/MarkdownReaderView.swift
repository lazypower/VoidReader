import SwiftUI
import VoidReaderCore

/// Renders markdown text as native SwiftUI content.
/// This is a placeholder that will be expanded with full markdown rendering.
struct MarkdownReaderView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let rendered = try? MarkdownRenderer.render(text) {
                Text(rendered)
                    .textSelection(.enabled)
            } else {
                // Fallback to plain text
                Text(text)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ScrollView {
        MarkdownReaderView(text: """
        # Heading 1
        ## Heading 2

        This is a paragraph with **bold** and *italic* text.

        - List item 1
        - List item 2
        """)
        .padding()
    }
}
