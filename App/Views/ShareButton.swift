import SwiftUI
import AppKit

/// A toolbar button that shows the macOS share sheet.
struct ShareButton: View {
    let text: String
    @State private var showingShare = false

    var body: some View {
        Button {
            showingShare = true
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .background(
            ShareSheetPresenter(isPresented: $showingShare, items: shareItems)
        )
    }

    private var shareItems: [Any] {
        // Share the markdown text
        [text]
    }
}

/// Presents the NSSharingServicePicker when triggered.
struct ShareSheetPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let items: [Any]

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            DispatchQueue.main.async {
                let picker = NSSharingServicePicker(items: items)
                picker.delegate = context.coordinator
                picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
                isPresented = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, NSSharingServicePickerDelegate {
        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            // Optional: track which service was chosen
        }
    }
}
