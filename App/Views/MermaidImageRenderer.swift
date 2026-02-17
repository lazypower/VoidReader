import AppKit
import WebKit
import VoidReaderCore

/// Renders mermaid diagrams to images for printing/PDF export.
actor MermaidImageRenderer {

    /// Renders a mermaid diagram source to an NSImage.
    static func render(source: String, maxWidth: CGFloat = 500) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let renderer = WebViewRenderer(source: source, maxWidth: maxWidth) { image in
                    continuation.resume(returning: image)
                }
                renderer.start()
            }
        }
    }

    /// Renders multiple mermaid diagrams, returning a dictionary keyed by source.
    static func renderAll(sources: [String], maxWidth: CGFloat = 500) async -> [String: NSImage] {
        var results: [String: NSImage] = [:]

        // Render sequentially to avoid overwhelming the system
        for source in sources {
            if let image = await render(source: source, maxWidth: maxWidth) {
                results[source] = image
            }
        }

        return results
    }
}

/// Internal class that manages a WKWebView for rendering.
private class WebViewRenderer: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let source: String
    private let maxWidth: CGFloat
    private let completion: (NSImage?) -> Void
    private var webView: WKWebView?
    private var timeoutTask: DispatchWorkItem?

    init(source: String, maxWidth: CGFloat, completion: @escaping (NSImage?) -> Void) {
        self.source = source
        self.maxWidth = maxWidth
        self.completion = completion
        super.init()
    }

    func start() {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "sizeReporter")

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: maxWidth, height: 400), configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView

        // Timeout after 5 seconds
        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(with: nil)
        }
        timeoutTask = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)

        loadMermaid()
    }

    private func loadMermaid() {
        guard let webView = webView,
              let templateURL = Bundle.main.url(forResource: "mermaid-template", withExtension: "html"),
              var template = try? String(contentsOf: templateURL) else {
            finish(with: nil)
            return
        }

        // Escape the source for HTML
        let escapedSource = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        // Use default light theme for printing
        template = template
            .replacingOccurrences(of: "{{MERMAID_SOURCE}}", with: escapedSource)
            .replacingOccurrences(of: "{{MERMAID_THEME}}", with: "default")
            .replacingOccurrences(of: "{{MERMAID_THEME_VARIABLES}}", with: "{}")

        let resourcesURL = Bundle.main.resourceURL
        webView.loadHTMLString(template, baseURL: resourcesURL)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let width = body["width"] as? Int,
              let height = body["height"] as? Int,
              let success = body["success"] as? Bool,
              success else {
            finish(with: nil)
            return
        }

        // Resize webview to fit content and capture
        let size = NSSize(width: min(CGFloat(width) + 32, maxWidth), height: CGFloat(height) + 32)
        webView?.frame.size = size

        // Small delay to let layout settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.captureSnapshot()
        }
    }

    private func captureSnapshot() {
        guard let webView = webView else {
            finish(with: nil)
            return
        }

        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds

        webView.takeSnapshot(with: config) { [weak self] image, error in
            if let error = error {
                print("Mermaid snapshot error: \(error)")
                self?.finish(with: nil)
                return
            }

            // Convert to NSImage
            guard let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                self?.finish(with: nil)
                return
            }

            let nsImage = NSImage(cgImage: cgImage, size: webView.bounds.size)
            self?.finish(with: nsImage)
        }
    }

    private func finish(with image: NSImage?) {
        timeoutTask?.cancel()
        timeoutTask = nil

        // Clean up webview
        if let webView = webView {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "sizeReporter")
            webView.navigationDelegate = nil
        }
        webView = nil

        completion(image)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("Mermaid render failed: \(error)")
        finish(with: nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("Mermaid render failed: \(error)")
        finish(with: nil)
    }
}
