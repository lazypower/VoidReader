import Cocoa
import Quartz
import SwiftUI
import VoidReaderCore

class PreviewViewController: NSViewController, QLPreviewingController {

    override var nibName: NSNib.Name? {
        return nil
    }

    override func loadView() {
        self.view = NSView()
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        // Load the markdown file
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            handler(NSError(domain: "VoidReader", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Could not read markdown file"
            ]))
            return
        }

        // Create the SwiftUI preview view
        let previewView = QuickLookPreviewView(text: text)
        let hostingView = NSHostingView(rootView: previewView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // Add to view hierarchy
        view.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        handler(nil)
    }
}

/// SwiftUI view for Quick Look preview - simplified markdown rendering.
struct QuickLookPreviewView: View {
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(BlockRenderer.render(text)) { block in
                    QuickLookBlockView(block: block)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.purple.opacity(0.2)) // DEBUG: verify our extension loads
    }
}

/// Simplified block renderer for Quick Look (no interactivity needed).
private struct QuickLookBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .text(let attributedString):
            Text(attributedString)
                .textSelection(.enabled)

        case .table(let tableData):
            QuickLookTableView(data: tableData)

        case .taskList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.isChecked ? "checkmark.square.fill" : "square")
                            .foregroundColor(item.isChecked ? .green : .secondary)
                        Text(item.content)
                    }
                }
            }

        case .codeBlock(let codeData):
            VStack(alignment: .leading, spacing: 4) {
                if let lang = codeData.language {
                    Text(lang)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(codeData.code)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
            }

        case .image(let imageData):
            if let url = imageData.url, let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 600)
            } else {
                Text("Image: \(imageData.altText)")
                    .foregroundColor(.secondary)
            }

        case .mermaid(let mermaidData):
            // Show mermaid source in Quick Look (no WKWebView)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "chart.bar.doc.horizontal")
                    Text("Mermaid Diagram")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Text(mermaidData.source)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(6)
            }
        }
    }
}

/// Simple table view for Quick Look.
private struct QuickLookTableView: View {
    let data: TableData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 0) {
                ForEach(Array(data.headers.enumerated()), id: \.offset) { idx, header in
                    Text(header.content)
                        .font(.headline)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: alignment(for: idx))
                        .background(Color(nsColor: .controlBackgroundColor))
                }
            }

            Divider()

            // Rows
            ForEach(Array(data.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { idx, cell in
                        Text(cell.content)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: alignment(for: idx))
                    }
                }
                Divider()
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func alignment(for column: Int) -> Alignment {
        guard column < data.alignments.count else { return .leading }
        switch data.alignments[column] {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}
