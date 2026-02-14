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

/// Toolbar button that exports to PDF and shares it.
struct SharePDFButton: View {
    let text: String
    let documentName: String

    var body: some View {
        Button {
            sharePDF()
        } label: {
            Label("Share as PDF", systemImage: "doc.fill")
        }
    }

    private func sharePDF() {
        // Create a temporary PDF file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(documentName.replacingOccurrences(of: ".md", with: ".pdf"))

        // Generate PDF
        let printView = PrintableMarkdownView(text: text)

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 612, height: 792)
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobDisposition] = NSPrintInfo.JobDisposition.save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = tempURL

        let printOperation = NSPrintOperation(view: printView, printInfo: printInfo)
        printOperation.showsPrintPanel = false
        printOperation.showsProgressPanel = false

        if printOperation.run() {
            // Show share sheet with the PDF
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let window = NSApplication.shared.keyWindow {
                    let picker = NSSharingServicePicker(items: [tempURL])
                    picker.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
                }
            }
        }
    }
}
