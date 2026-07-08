import SwiftUI
import AppKit

/// Resolves the `NSWindow` hosting a SwiftUI view. Used so per-window logic —
/// e.g. only the front document responding to a global print command — can check
/// `isKeyWindow` instead of every open window acting on the same broadcast.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in onResolve(view?.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in onResolve(nsView?.window) }
    }
}
