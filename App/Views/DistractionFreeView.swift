import SwiftUI
import VoidReaderCore

/// Distraction-free writing/reading mode with minimal UI.
struct DistractionFreeView: View {
    @Binding var document: MarkdownDocument
    @Binding var isActive: Bool
    let isEditMode: Bool

    @State private var showControls = false
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var wasFullscreen = false
    @State private var expandedMermaidSource: String?

    var body: some View {
        ZStack {
            // Background
            Color(nsColor: .textBackgroundColor)
                .ignoresSafeArea()

            // Content
            ScrollView {
                if isEditMode {
                    TextEditor(text: $document.text)
                        .font(.system(size: 16, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 80)
                        .padding(.vertical, 60)
                        .frame(maxWidth: 800)
                } else {
                    MarkdownReaderView(
                        text: document.text,
                        onMermaidExpand: { source in expandedMermaidSource = source }
                    )
                        .padding(.horizontal, 80)
                        .padding(.vertical, 60)
                        .frame(maxWidth: 800, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)

            // Hover controls at top
            VStack {
                if showControls {
                    HStack {
                        Spacer()

                        Button(action: exitDistractionFree) {
                            Label("Exit", systemImage: "arrow.down.right.and.arrow.up.left")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
            }
        }
        .onHover { hovering in
            // Only show controls when hovering near top
            // This is a simplified version - ideally track mouse position
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Show controls when dragging near top of screen
                    if value.location.y < 50 {
                        showControlsTemporarily()
                    }
                }
        )
        .onAppear {
            // Show controls briefly on enter
            showControlsTemporarily()

            // Enter fullscreen if not already
            if let window = NSApplication.shared.keyWindow {
                wasFullscreen = window.styleMask.contains(.fullScreen)
                if !wasFullscreen {
                    window.toggleFullScreen(nil)
                }
            }
        }
        .onDisappear {
            // Exit fullscreen if we entered it
            if !wasFullscreen, let window = NSApplication.shared.keyWindow {
                if window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil)
                }
            }
        }
        .onExitCommand {
            exitDistractionFree()
        }
        // Track mouse movement for showing controls
        .background(
            MouseTrackingView { point in
                if point.y < 60 {
                    showControlsTemporarily()
                }
            }
        )
        // Mermaid expand overlay
        .overlay {
            if let source = expandedMermaidSource {
                MermaidExpandedOverlay(
                    source: source,
                    isPresented: Binding(
                        get: { expandedMermaidSource != nil },
                        set: { if !$0 { expandedMermaidSource = nil } }
                    )
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expandedMermaidSource != nil)
    }

    private func showControlsTemporarily() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls = true
        }

        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showControls = false
                    }
                }
            }
        }
    }

    private func exitDistractionFree() {
        withAnimation {
            isActive = false
        }
    }
}

/// Tracks mouse movement within the view.
struct MouseTrackingView: NSViewRepresentable {
    let onMouseMove: (NSPoint) -> Void

    func makeNSView(context: Context) -> MouseTrackingNSView {
        let view = MouseTrackingNSView()
        view.onMouseMove = onMouseMove
        return view
    }

    func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {
        nsView.onMouseMove = onMouseMove
    }
}

class MouseTrackingNSView: NSView {
    var onMouseMove: ((NSPoint) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )

        if let area = trackingArea {
            addTrackingArea(area)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Convert to top-origin coordinates
        let flippedY = bounds.height - point.y
        onMouseMove?(NSPoint(x: point.x, y: flippedY))
    }
}

#Preview {
    DistractionFreeView(
        document: .constant(MarkdownDocument(text: "# Focus\n\nWrite without distraction.")),
        isActive: .constant(true),
        isEditMode: false
    )
}
