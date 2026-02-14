import SwiftUI
import VoidReaderCore

/// Renders a code block with copy button.
struct CodeBlockView: View {
    let data: CodeBlockData
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language badge + copy button
            HStack {
                if let language = data.language, !language.isEmpty {
                    Text(language)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
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
                                .font(.system(size: 11))
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

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(data.code)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
        .cornerRadius(8)
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

#Preview {
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
