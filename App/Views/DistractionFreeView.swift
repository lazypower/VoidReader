import SwiftUI
import VoidReaderCore

/// Distraction-free writing/reading mode with minimal UI.
struct DistractionFreeView: View {
    @Binding var document: MarkdownDocument
    @Binding var isActive: Bool
    let isEditMode: Bool

    @State private var expandedMermaidSource: String?
    @State private var expandedImageData: ExpandedImageData?
    @State private var wasFullscreen = false

    var body: some View {
        ZStack {
            // Background
            Color(nsColor: .textBackgroundColor)
                .ignoresSafeArea()

            // Content - isolated in its own view to prevent re-renders from control state
            DistractionFreeContentView(
                document: $document,
                isEditMode: isEditMode,
                onMermaidExpand: { source in expandedMermaidSource = source }
            )
            .environment(\.onImageExpand) { imageData in expandedImageData = imageData }

            // Hover controls - has its own state, isolated from content
            DistractionFreeControlsOverlay(onExit: exitDistractionFree)
        }
        .onAppear {
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
        // Expand overlays
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
            } else if let imageData = expandedImageData {
                ImageExpandedOverlay(
                    image: imageData.image,
                    altText: imageData.altText,
                    isPresented: Binding(
                        get: { expandedImageData != nil },
                        set: { if !$0 { expandedImageData = nil } }
                    )
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expandedMermaidSource != nil || expandedImageData != nil)
    }

    private func exitDistractionFree() {
        withAnimation {
            isActive = false
        }
    }
}

/// Content view - isolated so control state changes don't cause re-renders.
private struct DistractionFreeContentView: View {
    @Binding var document: MarkdownDocument
    let isEditMode: Bool
    let onMermaidExpand: (String) -> Void

    var body: some View {
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
                    onMermaidExpand: onMermaidExpand
                )
                    .padding(.horizontal, 80)
                    .padding(.vertical, 60)
                    .frame(maxWidth: 800, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Controls overlay with its own state - changes here don't affect content.
private struct DistractionFreeControlsOverlay: View {
    let onExit: () -> Void

    @State private var showControls = false
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            // Full-screen mouse tracking layer - passes through all events
            TopZoneDetectorView(onEnterTopZone: showControlsTemporarily)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            // Controls bar - only this receives clicks
            if showControls {
                HStack {
                    Spacer()

                    Button(action: onExit) {
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
        }
        .onAppear {
            showControlsTemporarily()
        }
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
}

/// Detects when mouse enters top zone - all state managed in NSView to avoid SwiftUI churn.
struct TopZoneDetectorView: NSViewRepresentable {
    let onEnterTopZone: () -> Void

    func makeNSView(context: Context) -> TopZoneDetectorNSView {
        let view = TopZoneDetectorNSView()
        view.onEnterTopZone = onEnterTopZone
        return view
    }

    func updateNSView(_ nsView: TopZoneDetectorNSView, context: Context) {
        nsView.onEnterTopZone = onEnterTopZone
    }
}

class TopZoneDetectorNSView: NSView {
    var onEnterTopZone: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var wasInTopZone = false  // Track state here, not in SwiftUI

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
        let isInTopZone = flippedY < 60

        // Only callback when entering the zone, not while in it or leaving
        if isInTopZone && !wasInTopZone {
            onEnterTopZone?()
        }
        wasInTopZone = isInTopZone
    }
}

#Preview {
    DistractionFreeView(
        document: .constant(MarkdownDocument(text: "# Focus\n\nWrite without distraction.")),
        isActive: .constant(true),
        isEditMode: false
    )
}
