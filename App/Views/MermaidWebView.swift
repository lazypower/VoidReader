import SwiftUI
import WebKit
import VoidReaderCore

/// WKWebView subclass that passes scroll events to parent.
class ScrollPassthroughWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        // Forward scroll events to next responder (parent scroll view)
        nextResponder?.scrollWheel(with: event)
    }
}

/// A SwiftUI view that renders mermaid diagrams using WKWebView.
struct MermaidWebView: NSViewRepresentable {
    let source: String
    @Binding var renderedHeight: CGFloat
    var allowsInteraction: Bool = false  // Enable zoom/pan for expanded view
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Add message handler for size reporting
        config.userContentController.add(context.coordinator, name: "sizeReporter")

        // Use passthrough for inline, regular for expanded (interactive)
        let webView: WKWebView
        if allowsInteraction {
            webView = WKWebView(frame: .zero, configuration: config)
            webView.allowsMagnification = true
        } else {
            webView = ScrollPassthroughWebView(frame: .zero, configuration: config)
        }

        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // Transparent background

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only reload if source changed
        if context.coordinator.lastSource != source || context.coordinator.lastColorScheme != colorScheme {
            context.coordinator.lastSource = source
            context.coordinator.lastColorScheme = colorScheme
            loadMermaid(in: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(heightBinding: $renderedHeight)
    }

    private func loadMermaid(in webView: WKWebView) {
        guard let templateURL = Bundle.main.url(forResource: "mermaid-template", withExtension: "html"),
              var template = try? String(contentsOf: templateURL) else {
            // Fallback: show error message
            webView.loadHTMLString("<html><body><p style='color:red;'>Failed to load mermaid template</p></body></html>", baseURL: nil)
            return
        }

        // Escape the source for HTML
        let escapedSource = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        // Determine theme based on color scheme
        let theme = colorScheme == .dark ? "dark" : "default"

        // Replace placeholders
        template = template
            .replacingOccurrences(of: "{{MERMAID_SOURCE}}", with: escapedSource)
            .replacingOccurrences(of: "{{MERMAID_THEME}}", with: theme)

        // Load with base URL pointing to resources for mermaid.min.js
        let resourcesURL = Bundle.main.resourceURL
        webView.loadHTMLString(template, baseURL: resourcesURL)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastSource: String?
        var lastColorScheme: ColorScheme?
        var heightBinding: Binding<CGFloat>

        init(heightBinding: Binding<CGFloat>) {
            self.heightBinding = heightBinding
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let height = body["height"] as? Int else {
                return
            }

            // Update the height binding on main thread
            DispatchQueue.main.async {
                // Add some padding for the container
                self.heightBinding.wrappedValue = CGFloat(height) + 16
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Diagram rendered
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Mermaid WebView navigation failed: \(error)")
        }
    }
}

/// A block view for mermaid diagrams with loading state and error handling.
struct MermaidBlockView: View {
    let data: MermaidData
    @State private var height: CGFloat = 100 // Start smaller, will expand
    @State private var showExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with mermaid icon/label and expand button
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundColor(.secondary)
                Text("Mermaid Diagram")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    showExpanded = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Expand diagram")
            }

            // WebView - height adjusts to content
            MermaidWebView(source: data.source, renderedHeight: $height)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .animation(.easeInOut(duration: 0.2), value: height)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showExpanded) {
            MermaidExpandedView(source: data.source)
        }
    }
}

/// Expanded overlay view for viewing complex diagrams.
struct MermaidExpandedView: View {
    let source: String
    @Environment(\.dismiss) private var dismiss
    @State private var renderedHeight: CGFloat = 400

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Mermaid Diagram")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Interactive diagram area with zoom/pan
            MermaidWebView(source: source, renderedHeight: $renderedHeight, allowsInteraction: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 700, minHeight: 500)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Flowchart") {
    ScrollView {
        MermaidBlockView(data: MermaidData(source: """
            flowchart TD
                A[Start] --> B{Is it working?}
                B -->|Yes| C[Great!]
                B -->|No| D[Debug]
                D --> B
            """))
            .padding()
    }
    .frame(width: 600, height: 400)
}

#Preview("Sequence Diagram") {
    ScrollView {
        MermaidBlockView(data: MermaidData(source: """
            sequenceDiagram
                Alice->>John: Hello John, how are you?
                John-->>Alice: Great!
                Alice-)John: See you later!
            """))
            .padding()
    }
    .frame(width: 600, height: 400)
}
