#if DEBUG
import AppKit
import SwiftUI
import VoidReaderCore
import os.signpost

/// Debug-only autoscroll driver for performance profiling under
/// `make profile AUTOSCROLL=fast|slow`.
///
/// Mounts a zero-size `NSView` inside the reader's SwiftUI `ScrollView`,
/// walks the superview chain to find the enclosing `NSScrollView`, and
/// programmatically scrolls top → bottom at one of two preset speeds.
/// Wraps the driven motion in a `scrollDriver` signpost interval so the
/// trace has a ground-truth lane for the "user scrolling" window.
///
/// ## Why this is safe to ship (behind DEBUG)
/// - `#if DEBUG` guards the entire file — zero impact on Release.
/// - Runtime gate on `VOID_READER_AUTOSCROLL=1` — Debug local runs
///   (`make run-debug`) don't auto-scroll unless explicitly asked.
/// - No visual mutation: we only drive `NSClipView.scroll(to:)` on the
///   existing scroll view. No view hierarchy changes, no redraws beyond
///   what a human wheel-scroll would cause.
///
/// ## Env vars
/// - `VOID_READER_AUTOSCROLL` — `1` to enable. Default: disabled.
/// - `VOID_READER_AUTOSCROLL_SPEED` — `fast` (default, ~24000 pt/s) or
///   `slow` (~3600 pt/s). Fast approximates a wheel-fling; slow
///   approximates steady two-finger drag.
/// - `VOID_READER_AUTOSCROLL_DELAY` — seconds to wait after the
///   document opens before starting the scroll. Default: 3.0. Gives
///   initial parse / highlight / measurement prefetch time to settle so
///   the scroll pass stresses steady-state behavior, not cold-start.
/// - `VOID_READER_AUTOSCROLL_TERMINATE` — `1` (default) to call
///   `NSApp.terminate` when the scroll reaches the bottom. Allows
///   `xctrace record --launch` to exit cleanly. Set to `0` to keep the
///   app alive (e.g., for manual follow-up).
struct ScrollAutoDriver: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        // Non-enabled case still returns a view so SwiftUI's layout
        // invariants hold — we just skip the scroll driver wiring.
        guard ProcessInfo.processInfo.environment["VOID_READER_AUTOSCROLL"] == "1" else {
            return NSView(frame: .zero)
        }
        return AutoDriverView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class AutoDriverView: NSView {
    private var timer: Timer?
    private var scrollView: NSScrollView?
    private var signpostState: OSSignpostIntervalState?
    private let signposter = Signposts.signposter(for: .scroll)
    private var y: CGFloat = 0
    private var maxY: CGFloat = 0
    private var pointsPerTick: CGFloat = 400

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Walk up the superview chain to find the SwiftUI-bridged
        // NSScrollView. Matches the pattern in `ScrollObserverView`.
        var current: NSView? = superview
        while let view = current {
            if let sv = view as? NSScrollView {
                scrollView = sv
                break
            }
            current = view.superview
        }
        guard scrollView != nil else {
            DebugLog.warning(.scroll, "AutoDriverView: no enclosing NSScrollView found")
            return
        }

        let delay = Double(ProcessInfo.processInfo.environment["VOID_READER_AUTOSCROLL_DELAY"] ?? "3.0") ?? 3.0
        DebugLog.info(.scroll, "AutoDriverView: scheduled start in \(delay)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.start()
        }
    }

    private func start() {
        guard let sv = scrollView, let docView = sv.documentView else {
            DebugLog.warning(.scroll, "AutoDriverView: scrollView or documentView missing at start")
            return
        }

        let speed = ProcessInfo.processInfo.environment["VOID_READER_AUTOSCROLL_SPEED"] ?? "fast"
        // ~60Hz tick; fast ≈ 24000 pt/s (wheel-fling territory), slow
        // ≈ 3600 pt/s (steady two-finger drag).
        pointsPerTick = (speed == "slow") ? 60 : 400

        let docHeight = docView.frame.height
        let clipHeight = sv.contentView.bounds.height
        maxY = max(0, docHeight - clipHeight)
        y = 0

        DebugLog.info(
            .scroll,
            "AutoDriverView: starting scroll speed=\(speed) docHeight=\(docHeight) clipHeight=\(clipHeight) maxY=\(maxY)"
        )

        signpostState = signposter.beginInterval(
            "scrollDriver",
            id: signposter.makeSignpostID(),
            "speed=\(speed) maxY=\(Int(self.maxY))"
        )

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            self.tick(timer: t)
        }
    }

    private func tick(timer t: Timer) {
        guard let sv = scrollView else {
            t.invalidate()
            finish()
            return
        }
        y += pointsPerTick
        if y >= maxY {
            y = maxY
            sv.contentView.scroll(to: NSPoint(x: 0, y: y))
            sv.reflectScrolledClipView(sv.contentView)
            t.invalidate()
            finish()
            return
        }
        sv.contentView.scroll(to: NSPoint(x: 0, y: y))
        sv.reflectScrolledClipView(sv.contentView)
    }

    private func finish() {
        if let state = signpostState {
            signposter.endInterval("scrollDriver", state, "endY=\(Int(self.y))")
            signpostState = nil
        }
        DebugLog.info(.scroll, "AutoDriverView: scroll complete at y=\(y)")

        let terminate = ProcessInfo.processInfo.environment["VOID_READER_AUTOSCROLL_TERMINATE"] ?? "1"
        guard terminate == "1" else { return }
        // Short pause so the last frames land in the trace before we exit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            DebugLog.info(.scroll, "AutoDriverView: terminating app")
            NSApp.terminate(nil)
        }
    }

    deinit { timer?.invalidate() }
}
#endif
