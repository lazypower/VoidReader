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
    var errorMessage: Binding<String>? = nil
    var allowsInteraction: Bool = false  // Enable zoom/pan for expanded view
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedThemeID") private var selectedThemeID: String = "system"

    /// Current theme from registry
    private var currentTheme: AppTheme {
        ThemeRegistry.shared.themeOrDefault(id: selectedThemeID)
    }

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
        // Reload if source, colorScheme, or theme changed
        if context.coordinator.lastSource != source ||
           context.coordinator.lastColorScheme != colorScheme ||
           context.coordinator.lastThemeID != selectedThemeID {
            context.coordinator.lastSource = source
            context.coordinator.lastColorScheme = colorScheme
            context.coordinator.lastThemeID = selectedThemeID
            loadMermaid(in: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(heightBinding: $renderedHeight, errorBinding: $hasError, errorMessageBinding: errorMessage)
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

        // Get theme name and variables
        let themeName = currentTheme.mermaidThemeName(for: colorScheme)
        let themeVars = currentTheme.mermaidThemeVariables(for: colorScheme)

        // Convert theme variables to JSON
        let themeVarsJSON: String
        if themeVars.isEmpty {
            themeVarsJSON = "{}"
        } else if let jsonData = try? JSONSerialization.data(withJSONObject: themeVars),
                  let jsonString = String(data: jsonData, encoding: .utf8) {
            themeVarsJSON = jsonString
        } else {
            themeVarsJSON = "{}"
        }

        // Replace placeholders
        template = template
            .replacingOccurrences(of: "{{MERMAID_SOURCE}}", with: escapedSource)
            .replacingOccurrences(of: "{{MERMAID_THEME}}", with: themeName)
            .replacingOccurrences(of: "{{MERMAID_THEME_VARIABLES}}", with: themeVarsJSON)

        // Load with base URL pointing to resources for mermaid.min.js
        let resourcesURL = Bundle.main.resourceURL
        webView.loadHTMLString(template, baseURL: resourcesURL)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastSource: String?
        var lastColorScheme: ColorScheme?
        var lastThemeID: String?
        var heightBinding: Binding<CGFloat>
        var errorBinding: Binding<Bool>
        var errorMessageBinding: Binding<String>?

        init(heightBinding: Binding<CGFloat>, errorBinding: Binding<Bool>, errorMessageBinding: Binding<String>? = nil) {
            self.heightBinding = heightBinding
            self.errorBinding = errorBinding
            self.errorMessageBinding = errorMessageBinding
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let height = body["height"] as? Int else {
                return
            }

            let success = body["success"] as? Bool ?? true
            let errorMessage = body["error"] as? String

            // Update bindings on main thread
            DispatchQueue.main.async {
                if success {
                    self.heightBinding.wrappedValue = CGFloat(height) + 16
                    self.errorBinding.wrappedValue = false
                } else {
                    self.errorMessageBinding?.wrappedValue = errorMessage ?? "Unknown rendering error"
                    self.errorBinding.wrappedValue = true
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // For expanded view, don't auto-magnify - let user zoom interactively
            // The diagram will render centered at natural size
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Mermaid WebView navigation failed: \(error)")
        }
    }
}

/// Cache of mermaid sources that failed to render (source → error message).
private nonisolated(unsafe) var mermaidErrorCache = [String: String]()

/// A block view for mermaid diagrams with loading state and error handling.
struct MermaidBlockView: View {
    let data: MermaidData
    var onExpand: ((String) -> Void)? = nil
    @State private var renderedHeight: CGFloat = 0
    @State private var hasError = false
    @State private var isRendered = false
    @State private var errorMessage: String = ""
    @State private var showingError = false

    /// Check cache synchronously — prevents WebView creation on recycled views
    private var cachedError: String? {
        mermaidErrorCache[data.source]
    }

    // Display height animates from 0 to final height
    private var displayHeight: CGFloat {
        isRendered ? renderedHeight : 0
    }

    private var isError: Bool {
        hasError || cachedError != nil
    }

    private var displayErrorMessage: String {
        if !errorMessage.isEmpty { return errorMessage }
        return cachedError ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with mermaid icon/label and expand button
            HStack {
                Image(systemName: isError ? "exclamationmark.triangle" : "chart.bar.doc.horizontal")
                    .foregroundColor(isError ? .orange : .secondary)
                Text(isError ? "Mermaid Error" : "Mermaid Diagram")
                    .font(.caption)
                    .foregroundColor(isError ? .orange : .secondary)

                if isError && !displayErrorMessage.isEmpty {
                    Button {
                        showingError.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Show error details")
                    .popover(isPresented: $showingError) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Mermaid Render Error")
                                .font(.headline)
                            ScrollView {
                                Text(displayErrorMessage)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                        .frame(width: 420)
                        .frame(maxHeight: 300)
                    }
                }

                Spacer()
                if !isError && isRendered {
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

            if isError {
                // Fallback: show raw mermaid code
                CodeBlockView(data: CodeBlockData(code: data.source, language: "mermaid"))
            } else {
                // WebView - grows in smoothly when rendered
                MermaidWebView(source: data.source, renderedHeight: $renderedHeight, hasError: $hasError, errorMessage: $errorMessage)
                    .frame(height: max(displayHeight, 1)) // min 1 to keep WebView alive
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    .opacity(isRendered ? 1 : 0)
                    .clipped()
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.35), value: isRendered)
        .onChange(of: hasError) { _, isError in
            if isError {
                mermaidErrorCache[data.source] = errorMessage.isEmpty ? "Unknown error" : errorMessage
            }
        }
        .onChange(of: renderedHeight) { _, newValue in
            // Mark as rendered once we get real dimensions
            if newValue > 0 && !isRendered {
                isRendered = true
            }
        }
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

                    // Interactive diagram - fills available space, auto-scaled to fit
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
