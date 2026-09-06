import SwiftUI
import AppKit
import VoidReaderCore

/// Observes scroll position at the NSScrollView level for efficient percentage tracking.
/// This avoids SwiftUI's view update cycle for better performance on large documents.
struct ScrollPercentageObserver: NSViewRepresentable {
    let onPositionChange: (ReaderScrollPosition) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollObserverView()
        view.onPositionChange = onPositionChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let observer = nsView as? ScrollObserverView {
            observer.onPositionChange = onPositionChange
            observer.refresh()
        }
    }
}

/// A snapshot of the reader's actual AppKit scroll geometry. The scroll view
/// owns all three values, so percentage display and persistence cannot drift
/// onto a parallel SwiftUI height estimate.
struct ReaderScrollPosition: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let visibleHeight: CGFloat

    var fraction: Double {
        let scrollableHeight = contentHeight - visibleHeight
        guard scrollableHeight > 0 else { return 0 }
        return min(max(Double(offset / scrollableHeight), 0), 1)
    }

    var percent: Int {
        Int((fraction * 100).rounded())
    }
}

/// A minimal NSView that observes its enclosing scroll view.
private class ScrollObserverView: NSView {
    var onPositionChange: ((ReaderScrollPosition) -> Void)?
    private var scrollView: NSScrollView?
    private weak var observedDocumentView: NSView?
    private var debounceTask: DispatchWorkItem?
    private var lastReportedPosition: ReaderScrollPosition?
    private var lastLiveReportTime: TimeInterval = 0
    private static let liveReportInterval: TimeInterval = 0.1

    /// Counter for sampled `scrollTick` signpost emission. We always emit on tick #1 of a
    /// burst (so brief scrolls register) and then every Nth tick (so long scrolls show as
    /// a density envelope rather than timeline static). Reset to 0 in `reportPosition`
    /// when the debounced "scroll settled" handler runs, so each burst is independent.
    private var scrollTickCounter: Int = 0
    private static let scrollTickSampleEvery = 10

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reconnectIfNeeded()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        // SwiftUI can put the representable in a window before its final
        // superview chain reaches NSScrollView. Retry after hierarchy changes.
        reconnectIfNeeded()
    }

    private func setupObserver() {
        guard let scrollView = scrollView,
              let documentView = scrollView.documentView else { return }

        let clipView = scrollView.contentView

        // Observe bounds changes on the clip view (scroll position)
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollDidChange),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )

        // Progressive rendering and large native surfaces can change the
        // scrollable range without changing the current offset. Observe the
        // document frame so the footer is corrected as soon as layout lands.
        documentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentFrameDidChange),
            name: NSView.frameDidChangeNotification,
            object: documentView
        )
        observedDocumentView = documentView

        // Report initial position
        refresh()
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

        // Report live at no more than 10Hz, and only publish when the rounded
        // percentage changes. This keeps the footer responsive without making
        // ContentView invalidate on every 60/120Hz bounds notification.
        let now = Date.timeIntervalSinceReferenceDate
        if now - lastLiveReportTime >= Self.liveReportInterval {
            lastLiveReportTime = now
            reportPosition(force: false)
        }

        // Always capture one exact position after motion settles. Persistence
        // uses its fraction, so it should not be limited to integer-percent
        // boundaries.
        debounceTask?.cancel()

        let task = DispatchWorkItem { [weak self] in
            self?.scrollTickCounter = 0
            self?.reportPosition(force: true)
        }
        debounceTask = task

        // 150ms debounce
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
    }

    @objc private func documentFrameDidChange(_ notification: Notification) {
        scheduleReport()
    }

    func refresh() {
        reconnectIfNeeded()
    }

    private func reconnectIfNeeded() {
        guard window != nil else {
            removeObservers()
            scrollView = nil
            return
        }

        var ancestor = superview
        var enclosingScrollView: NSScrollView?
        while let view = ancestor {
            if let candidate = view as? NSScrollView {
                enclosingScrollView = candidate
                break
            }
            ancestor = view.superview
        }

        guard let enclosingScrollView else {
            DebugLog.log(.scroll, "ScrollObserverView: no enclosing NSScrollView yet")
            return
        }
        let documentView = enclosingScrollView.documentView
        if scrollView !== enclosingScrollView || observedDocumentView !== documentView {
            removeObservers()
            scrollView = enclosingScrollView
            DebugLog.log(.scroll, "ScrollObserverView: attached to NSScrollView")
            setupObserver()
        } else {
            scheduleReport()
        }
    }

    private func scheduleReport() {
        debounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.reportPosition(force: true)
        }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: task)
    }

    private func reportPosition(force: Bool) {
        guard let scrollView, let documentView = scrollView.documentView else { return }

        let clipBounds = scrollView.contentView.bounds
        let position = ReaderScrollPosition(
            offset: clipBounds.origin.y,
            contentHeight: documentView.frame.height,
            visibleHeight: clipBounds.height
        )

        let dimensionsChanged = lastReportedPosition.map {
            $0.contentHeight != position.contentHeight || $0.visibleHeight != position.visibleHeight
        } ?? true
        let percentChanged = lastReportedPosition?.percent != position.percent
        lastReportedPosition = position

        if force || dimensionsChanged || percentChanged {
            DebugLog.log(
                .scroll,
                "ScrollObserverView: offset=\(Int(position.offset)) range=\(Int(position.contentHeight - position.visibleHeight)) percent=\(position.percent)"
            )
            onPositionChange?(position)
        }
    }

    private func removeObservers() {
        if let scrollView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }
        if let observedDocumentView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.frameDidChangeNotification,
                object: observedDocumentView
            )
        }
        observedDocumentView = nil
    }

    deinit {
        removeObservers()
        debounceTask?.cancel()
    }
}
