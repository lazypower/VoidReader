import SwiftUI
import AppKit
import VoidReaderCore

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

    /// Counter for sampled `scrollTick` signpost emission. We always emit on tick #1 of a
    /// burst (so brief scrolls register) and then every Nth tick (so long scrolls show as
    /// a density envelope rather than timeline static). Reset to 0 in `reportPosition`
    /// when the debounced "scroll settled" handler runs, so each burst is independent.
    private var scrollTickCounter: Int = 0
    private static let scrollTickSampleEvery = 10

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
        // Sampled scrollTick signpost. Full-rate emission (~60Hz under active scrolling)
        // would drown the Instruments timeline; sampling at every 10th tick gives ~6Hz
        // density — enough to see the gesture envelope without static. Tick #1 is always
        // emitted so brief scrolls (< sample window) still show up in the trace.
        scrollTickCounter += 1
        if scrollTickCounter == 1 || scrollTickCounter % Self.scrollTickSampleEvery == 0 {
            Signposts.event("scrollTick", category: .scroll)
        }

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
        // Debounced — fires when scroll has been quiet for 150ms. Reset the scrollTick
        // sample counter so the next burst's tick #1 emits unconditionally.
        scrollTickCounter = 0

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
