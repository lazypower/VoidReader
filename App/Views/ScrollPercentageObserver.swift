import SwiftUI
import AppKit

/// Observes scroll position at the NSScrollView level for efficient percentage tracking.
/// This avoids SwiftUI's view update cycle for better performance on large documents.
struct ScrollPercentageObserver: NSViewRepresentable {
    let onPercentChange: (Int) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollObserverView()
        view.onPercentChange = onPercentChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let observer = nsView as? ScrollObserverView {
            observer.onPercentChange = onPercentChange
        }
    }
}

/// A minimal NSView that observes its enclosing scroll view.
private class ScrollObserverView: NSView {
    var onPercentChange: ((Int) -> Void)?
    private var scrollView: NSScrollView?
    private var debounceTask: DispatchWorkItem?
    private var lastReportedPercent: Int = -1

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        // Find the enclosing scroll view
        var current: NSView? = superview
        while let view = current {
            if let sv = view as? NSScrollView {
                scrollView = sv
                setupObserver()
                break
            }
            current = view.superview
        }
    }

    private func setupObserver() {
        guard let scrollView = scrollView,
              let clipView = scrollView.contentView as? NSClipView else { return }

        // Observe bounds changes on the clip view (scroll position)
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollDidChange),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )

        // Report initial position
        reportPosition()
    }

    @objc private func scrollDidChange(_ notification: Notification) {
        // Debounce updates - only report after scroll stops
        debounceTask?.cancel()

        let task = DispatchWorkItem { [weak self] in
            self?.reportPosition()
        }
        debounceTask = task

        // 150ms debounce
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
    }

    private func reportPosition() {
        guard let scrollView = scrollView,
              let documentView = scrollView.documentView else { return }

        let clipBounds = scrollView.contentView.bounds
        let docHeight = documentView.frame.height
        let visibleHeight = clipBounds.height

        // Calculate scroll percentage
        let scrollableHeight = docHeight - visibleHeight
        guard scrollableHeight > 0 else {
            if lastReportedPercent != 0 {
                lastReportedPercent = 0
                onPercentChange?(0)
            }
            return
        }

        let scrollPosition = clipBounds.origin.y
        let percent = Int((scrollPosition / scrollableHeight) * 100)
        let clampedPercent = max(0, min(100, percent))

        // Only report if changed
        if clampedPercent != lastReportedPercent {
            lastReportedPercent = clampedPercent
            onPercentChange?(clampedPercent)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        debounceTask?.cancel()
    }
}
