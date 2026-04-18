import SwiftUI
import VoidReaderCore

/// Invisible NSViewRepresentable that starts the FrameDropMonitor
/// and exposes stats via an NSTextField with accessibility identifier.
/// SwiftUI's accessibility system is unreliable for hidden elements,
/// so we use a native AppKit text field instead.
struct FrameDropOverlay: NSViewRepresentable {
    @ObservedObject private var monitor = FrameDropMonitor.shared

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.setAccessibilityIdentifier("frame-drop-container")

        // Invisible label that XCUITests can find
        let label = NSTextField(labelWithString: monitor.summary)
        label.setAccessibilityIdentifier("frame-drop-stats")
        label.font = NSFont.systemFont(ofSize: 1)
        label.textColor = .clear
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 1),
            label.heightAnchor.constraint(equalToConstant: 1),
        ])

        context.coordinator.label = label

        // Start frame drop monitoring
        DispatchQueue.main.async {
            FrameDropMonitor.shared.start(from: container)
        }

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.label?.stringValue = monitor.summary
        context.coordinator.label?.setAccessibilityLabel(monitor.summary)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        weak var label: NSTextField?
    }
}
