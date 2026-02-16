import SwiftUI
import WebKit

/// A SwiftUI view that renders LaTeX math using KaTeX in a WKWebView.
struct MathWebView: NSViewRepresentable {
    let latex: String
    let isBlock: Bool
    @Binding var renderedHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "mathRendered")

        let webView = ScrollPassthroughWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Reload if content or appearance changed
        if context.coordinator.lastLatex != latex ||
           context.coordinator.lastColorScheme != colorScheme {
            context.coordinator.lastLatex = latex
            context.coordinator.lastColorScheme = colorScheme
            loadMath(in: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(heightBinding: $renderedHeight)
    }

    private func loadMath(in webView: WKWebView) {
        guard let templateURL = Bundle.main.url(forResource: "math-template", withExtension: "html"),
              var template = try? String(contentsOf: templateURL) else {
            webView.loadHTMLString("<html><body style='color:red;'>Failed to load math template</body></html>", baseURL: nil)
            return
        }

        // URL-encode the LaTeX for safe transport
        let encodedLatex = latex.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? latex

        // Text color based on appearance
        let textColor = colorScheme == .dark ? "#e0e0e0" : "#1a1a1a"
        let displayMode = isBlock ? "block-mode" : "inline-mode"

        template = template
            .replacingOccurrences(of: "{{LATEX_CONTENT}}", with: encodedLatex)
            .replacingOccurrences(of: "{{TEXT_COLOR}}", with: textColor)
            .replacingOccurrences(of: "{{DISPLAY_MODE}}", with: displayMode)

        let resourcesURL = Bundle.main.resourceURL
        webView.loadHTMLString(template, baseURL: resourcesURL)
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var lastLatex: String?
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

            DispatchQueue.main.async {
                self.heightBinding.wrappedValue = CGFloat(height)
            }
        }
    }
}

/// A block view for display math ($$...$$) with smooth rendering.
struct MathBlockView: View {
    let latex: String
    @State private var renderedHeight: CGFloat = 0
    @State private var isRendered = false

    private var displayHeight: CGFloat {
        isRendered ? renderedHeight : 0
    }

    var body: some View {
        MathWebView(latex: latex, isBlock: true, renderedHeight: $renderedHeight)
            .frame(height: max(displayHeight, 1))
            .frame(maxWidth: .infinity)
            .opacity(isRendered ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: isRendered)
            .onChange(of: renderedHeight) { _, newValue in
                if newValue > 0 && !isRendered {
                    isRendered = true
                }
            }
    }
}

/// Inline math view ($...$) - renders inline with text.
struct InlineMathView: View {
    let latex: String
    @State private var renderedHeight: CGFloat = 20 // Default inline height
    @State private var isRendered = false

    var body: some View {
        MathWebView(latex: latex, isBlock: false, renderedHeight: $renderedHeight)
            .frame(height: isRendered ? renderedHeight : 20)
            .frame(minWidth: 20)
            .opacity(isRendered ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.15), value: isRendered)
            .onChange(of: renderedHeight) { _, newValue in
                if newValue > 0 && !isRendered {
                    isRendered = true
                }
            }
    }
}

#Preview("Block Math") {
    VStack(spacing: 20) {
        Text("Cluster Separation Index:")
        MathBlockView(latex: "CSI = \\frac{\\delta}{\\sigma} \\cdot \\log(n + 1)")

        Text("Boundary Collision Detection:")
        MathBlockView(latex: "|d(t, C_i) - d(t, C_j)| < \\epsilon")

        Text("Dynamic Epsilon:")
        MathBlockView(latex: "\\epsilon = \\alpha \\cdot \\text{median}(d(C_i, C_j)), \\quad \\alpha = 0.08")
    }
    .padding()
    .frame(width: 500, height: 400)
}

#Preview("Inline Math") {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            Text("The threshold")
            InlineMathView(latex: "\\epsilon = 0.08")
            Text("controls sensitivity.")
        }

        HStack {
            Text("Energy equals")
            InlineMathView(latex: "E = mc^2")
        }
    }
    .padding()
    .frame(width: 400, height: 200)
}
