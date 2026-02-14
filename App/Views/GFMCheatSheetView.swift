import SwiftUI

/// GFM (GitHub Flavored Markdown) syntax cheat sheet overlay.
struct GFMCheatSheetView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("GFM Cheat Sheet")
                    .font(.title2.bold())
                    .padding(.bottom, 4)

                syntaxSection("Headings") {
                    example("# H1", "## H2", "### H3")
                }

                syntaxSection("Emphasis") {
                    example("*italic* or _italic_")
                    example("**bold** or __bold__")
                    example("***bold italic***")
                    example("~~strikethrough~~")
                }

                syntaxSection("Links & Images") {
                    example("[link text](url)")
                    example("![alt text](image.png)")
                    example("<https://auto.link>")
                }

                syntaxSection("Code") {
                    example("`inline code`")
                    example("```language\ncode block\n```")
                }

                syntaxSection("Lists") {
                    example("- unordered item\n- another item")
                    example("1. ordered item\n2. second item")
                    example("- [x] task done\n- [ ] task todo")
                }

                syntaxSection("Blockquotes") {
                    example("> quoted text\n> continues here")
                }

                syntaxSection("Tables") {
                    example("""
                    | Left | Center | Right |
                    |:-----|:------:|------:|
                    | a    |   b    |     c |
                    """)
                }

                syntaxSection("Horizontal Rule") {
                    example("---")
                }
            }
            .padding(24)
        }
        .frame(width: 400, height: 500)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 20)
    }

    private func syntaxSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            content()
        }
    }

    private func example(_ lines: String...) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                    .cornerRadius(4)
            }
        }
    }
}

/// Monitors for Option+Shift+/ key combination.
struct CheatSheetKeyMonitor: ViewModifier {
    @Binding var isShowing: Bool
    @State private var eventMonitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                setupKeyMonitor()
            }
            .onDisappear {
                removeKeyMonitor()
            }
    }

    private func setupKeyMonitor() {
        // Monitor for key down (Option+Shift+/)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            // Option+Shift+/ = keyCode 44 (/) with option+shift modifiers
            let isOptionShiftSlash = event.keyCode == 44 &&
                event.modifierFlags.contains(.option) &&
                event.modifierFlags.contains(.shift)

            if isOptionShiftSlash {
                if event.type == .keyDown && !event.isARepeat {
                    isShowing = true
                } else if event.type == .keyUp {
                    isShowing = false
                }
                return nil // Consume the event
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

extension View {
    func cheatSheetOnHold(isShowing: Binding<Bool>) -> some View {
        modifier(CheatSheetKeyMonitor(isShowing: isShowing))
    }
}

#Preview {
    GFMCheatSheetView()
        .padding()
}
