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
    @Binding var hasError: Bool
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
        Coordinator(heightBinding: $renderedHeight, errorBinding: $hasError)
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
        var errorBinding: Binding<Bool>

        init(heightBinding: Binding<CGFloat>, errorBinding: Binding<Bool>) {
            self.heightBinding = heightBinding
            self.errorBinding = errorBinding
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let height = body["height"] as? Int else {
                return
            }

            let success = body["success"] as? Bool ?? true

            // Update bindings on main thread
            DispatchQueue.main.async {
                if success {
                    self.heightBinding.wrappedValue = CGFloat(height) + 16
                    self.errorBinding.wrappedValue = false
                } else {
                    self.errorBinding.wrappedValue = true
                }
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
    var onExpand: ((String) -> Void)? = nil
    @State private var height: CGFloat = 100 // Start smaller, will expand
    @State private var hasError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with mermaid icon/label and expand button
            HStack {
                Image(systemName: hasError ? "exclamationmark.triangle" : "chart.bar.doc.horizontal")
                    .foregroundColor(hasError ? .orange : .secondary)
                Text(hasError ? "Mermaid Error" : "Mermaid Diagram")
                    .font(.caption)
                    .foregroundColor(hasError ? .orange : .secondary)
                Spacer()
                if !hasError {
                    Button {
                        onExpand?(data.source)
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Expand diagram")
                }
            }

            if hasError {
                // Fallback: show raw mermaid code
                CodeBlockView(data: CodeBlockData(code: data.source, language: "mermaid"))
            } else {
                // WebView - height adjusts to content
                MermaidWebView(source: data.source, renderedHeight: $height, hasError: $hasError)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .animation(.easeInOut(duration: 0.2), value: height)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Full-window overlay for viewing complex diagrams.
struct MermaidExpandedOverlay: View {
    let source: String
    @Binding var isPresented: Bool
    @State private var renderedHeight: CGFloat = 400
    @State private var hasError = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dimmed background
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented = false
                        }
                    }

                // Diagram container - takes most of available space
                VStack(spacing: 0) {
                    // Header bar
                    HStack {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .foregroundColor(.secondary)
                        Text("Mermaid Diagram")
                            .font(.headline)

                        Spacer()

                        Text("Pinch to zoom • Scroll to pan")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(Color(nsColor: .windowBackgroundColor))

                    Divider()

                    // Interactive diagram - fills available space
                    MermaidWebView(source: source, renderedHeight: $renderedHeight, hasError: $hasError, allowsInteraction: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor))
                }
                .frame(width: geo.size.width * 0.9, height: geo.size.height * 0.9)
                .cornerRadius(12)
                .shadow(radius: 20)
            }
        }
        .transition(.opacity)
        .onExitCommand {
            withAnimation(.easeOut(duration: 0.2)) {
                isPresented = false
            }
        }
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
