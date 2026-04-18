import Foundation
import QuartzCore
import AppKit

/// Monitors frame drops during scroll by tracking main-thread stalls via CADisplayLink.
///
/// Usage:
///   1. Call `start(from:)` with any visible NSView to begin monitoring
///   2. Call `reset()` before a scroll test to zero counters
///   3. After scrolling, read `droppedFrames` and `totalFrames`
///   4. Call `stop()` when done
///
/// A frame is "dropped" when the interval between display link callbacks
/// exceeds 1.5x the expected frame duration (indicating the main thread
/// was blocked and missed a vsync).
public final class FrameDropMonitor: ObservableObject {
    public static let shared = FrameDropMonitor()

    @Published public private(set) var droppedFrames: Int = 0
    @Published public private(set) var totalFrames: Int = 0

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var isRunning = false

    /// Threshold multiplier for detecting a dropped frame.
    /// 1.5x expected interval = missed a vsync.
    private let dropThreshold: Double = 1.5

    private init() {}

    /// Start monitoring from a view (needed to create CADisplayLink on macOS).
    public func start(from view: NSView) {
        guard !isRunning else { return }
        isRunning = true
        lastTimestamp = 0

        displayLink = view.displayLink(target: self, selector: #selector(tick(_:)))
        displayLink?.add(to: .main, forMode: .common)

        DebugLog.log(.perf, "FrameDropMonitor started")
    }

    /// Reset counters (call before a scroll test interval).
    public func reset() {
        droppedFrames = 0
        totalFrames = 0
        lastTimestamp = 0
    }

    /// Stop monitoring.
    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
        isRunning = false
        DebugLog.log(.perf, "FrameDropMonitor stopped: \(droppedFrames) dropped / \(totalFrames) total frames")
    }

    @objc private func tick(_ link: CADisplayLink) {
        totalFrames += 1

        if lastTimestamp > 0 {
            let elapsed = link.timestamp - lastTimestamp
            let expected = link.duration

            if expected > 0 && elapsed > expected * dropThreshold {
                let missed = Int(elapsed / expected) - 1
                droppedFrames += max(1, missed)
            }
        }

        lastTimestamp = link.timestamp
    }

    /// Summary string for accessibility/debug.
    public var summary: String {
        "frames:\(totalFrames) dropped:\(droppedFrames)"
    }
}
