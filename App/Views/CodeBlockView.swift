import SwiftUI
import VoidReaderCore
import Highlightr

/// Shared highlighter instance for performance.
private let highlightr: Highlightr? = {
    let h = Highlightr()
    return h
}()

/// Renders a code block with syntax highlighting and copy button.
struct CodeBlockView: View {
    let data: CodeBlockData
    var fontSize: CGFloat = 13
    @State private var showCopied = false
    @Environment(\.colorScheme) private var colorScheme

    // Theme config - single point to change later
    private var themeName: String {
        colorScheme == .dark ? "atom-one-dark" : "atom-one-light"
    }

    // Badge font scales with code font
    private var badgeFontSize: CGFloat {
        max(9, fontSize * 0.85)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language badge + copy button
            HStack {
                if let language = data.language, !language.isEmpty {
                    Text(language)
                        .font(.system(size: badgeFontSize, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                        .cornerRadius(4)
                }

                Spacer()

                Button(action: copyCode) {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        if showCopied {
                            Text("Copied")
                                .font(.system(size: badgeFontSize))
                        }
                    }
                    .foregroundColor(showCopied ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Code content with syntax highlighting
            ScrollView(.horizontal, showsIndicators: false) {
                highlightedCode
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var highlightedCode: some View {
        if let highlighted = highlightCode() {
            Text(highlighted)
        } else {
            // Fallback to plain text
            Text(data.code)
                .font(.system(size: fontSize, design: .monospaced))
        }
    }

    private func highlightCode() -> AttributedString? {
        guard let highlightr = highlightr else { return nil }

        // Set theme based on color scheme
        highlightr.setTheme(to: themeName)

        // Use language hint or let Highlightr auto-detect
        let language = data.language?.lowercased()

        guard let nsAttr = highlightr.highlight(data.code, as: language) else {
            return nil
        }

        // Convert to mutable to adjust font size
        let mutableAttr = NSMutableAttributedString(attributedString: nsAttr)
        let fullRange = NSRange(location: 0, length: mutableAttr.length)

        // Update font to use our size while preserving monospace
        mutableAttr.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            let newFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            mutableAttr.addAttribute(.font, value: newFont, range: range)
        }

        // Convert NSAttributedString to SwiftUI AttributedString
        return try? AttributedString(mutableAttr, including: AttributeScopes.AppKitAttributes.self)
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(data.code, forType: .string)

        withAnimation {
            showCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopied = false
            }
        }
    }
}

#Preview("Swift") {
    CodeBlockView(data: CodeBlockData(
        code: """
        func greet(name: String) -> String {
            return "Hello, \\(name)!"
        }

        let message = greet(name: "World")
        print(message)
        """,
        language: "swift"
    ))
    .padding()
    .frame(width: 500)
}

#Preview("Python") {
    CodeBlockView(data: CodeBlockData(
        code: """
        def fibonacci(n):
            if n <= 1:
                return n
            return fibonacci(n-1) + fibonacci(n-2)

        for i in range(10):
            print(fibonacci(i))
        """,
        language: "python"
    ))
    .padding()
    .frame(width: 500)
}

#Preview("No Language") {
    CodeBlockView(data: CodeBlockData(
        code: "Some plain text code without language hint",
        language: nil
    ))
    .padding()
    .frame(width: 500)
}
