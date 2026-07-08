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
        // Signpost: mermaidRender — single interval covering the sequential render of all
        // diagrams; metadata records the count up front so the trace shows scale at a glance.
        let signposter = Signposts.signposter(for: .mermaid)
        let signpostID = signposter.makeSignpostID()
        let signpostState = signposter.beginInterval(
            "mermaidRender",
            id: signpostID,
            "diagrams=\(sources.count)"
        )
        defer { signposter.endInterval("mermaidRender", signpostState) }

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
    /// Off-screen host window. A windowless WKWebView receives no display frames,
    /// so the template's `requestAnimationFrame` size report never fires (render
    /// times out → blank), and `takeSnapshot` has nothing composited. Hosting the
    /// webview in a window parked far off-screen restores both.
    private var hostWindow: NSWindow?
    private var timeoutTask: DispatchWorkItem?
    /// Guards against resuming the continuation twice. `finish` is reachable from
    /// several racing paths — the 5s timeout, the size-report handler, the
    /// snapshot callback, and navigation-failure delegates — and the size report
    /// resizes the webview, which re-fires the template's debounced
    /// ResizeObserver. All paths run on the main thread, so a plain flag is
    /// enough; a second `finish` (which would fatally double-resume) is dropped.
    private var finished = false

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

        // Park the webview in an off-screen window so it gets display frames
        // (rAF fires, size reports, snapshot composites) without ever being seen.
        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        self.hostWindow = window

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

        // Resize to fit content and capture. The webview is the window's content
        // view, so resize through the window.
        let size = NSSize(width: min(CGFloat(width) + 32, maxWidth), height: CGFloat(height) + 32)
        hostWindow?.setContentSize(size)
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

        // Render via createPDF rather than takeSnapshot. takeSnapshot needs the
        // webview composited on-screen; createPDF renders the DOM headlessly
        // (WebKit's print path), so it works for an off-screen export webview.
        // NSImage loads the PDF representation directly.
        let config = WKPDFConfiguration()
        config.rect = webView.bounds

        webView.createPDF(configuration: config) { [weak self] result in
            switch result {
            case .success(let data):
                if let image = NSImage(data: data), image.size.width > 0 {
                    self?.finish(with: image)
                } else {
                    self?.finish(with: nil)
                }
            case .failure(let error):
                print("Mermaid PDF render error: \(error)")
                self?.finish(with: nil)
            }
        }
    }

    private func finish(with image: NSImage?) {
        guard !finished else { return }
        finished = true

        timeoutTask?.cancel()
        timeoutTask = nil

        // Clean up webview + its off-screen host window
        if let webView = webView {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "sizeReporter")
            webView.navigationDelegate = nil
        }
        webView = nil
        hostWindow?.orderOut(nil)
        hostWindow?.contentView = nil
        hostWindow = nil

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
