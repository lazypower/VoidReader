import Foundation
import os.signpost

/// `OSSignposter`-based instrumentation for Instruments profiling.
///
/// Signposts are intended for visual diagnosis in Instruments (Time Profiler, Animation Hitches,
/// Allocations, Points of Interest). They complement — and do not replace — `DebugLog`
/// (Console.app) and `FrameDropMonitor` (in-app overlay). See
/// `openspec/changes/add-performance-instrumentation/design.md` for the boundaries.
///
/// ## Subsystem & Category Layout
/// Each `SignpostCategory` gets its own `OSSignposter` with a stable subsystem identifier of the
/// form `place.wabash.VoidReader.<category>`. This namespace is intentionally distinct from
/// `DebugLog`'s `com.voidreader.debug.*` so Instruments' subsystem filter can isolate signposts
/// cleanly without pulling in DebugLog noise.
///
/// The OSLog *category* matches the subsystem suffix (`rendering`, `lifecycle`, …) — these end
/// up grouping signposts in Instruments' os_signpost summary view. We deliberately do NOT use
/// the `"PointsOfInterest"` category: the built-in Points of Interest instrument has a hardcoded
/// subsystem allowlist (only `com.apple.neappprivacy` and a handful of Apple subsystems are
/// permitted to render in that lane), so routing our signposts there causes them to vanish from
/// both the POI lane *and* the generic os_signpost lane (which filters POI out). This was
/// learned empirically during the first profile run — see `make profile` in the Makefile, which
/// adds the `os_signpost` instrument explicitly so per-domain categories surface in the trace.
///
/// ## Zero-Overhead Contract
/// `OSSignposter` is designed to be effectively free when Instruments is not recording. Hot-loop
/// signals (e.g., `scrollTick`) use `event(_:category:)` rather than `interval(...)` to avoid
/// `begin`/`end` pairing overhead. See `MarkdownPerformanceTests` and `SignpostsTests` for the
/// bounded-time assertions that enforce this.
///
/// ## Usage
/// ```swift
/// Signposts.interval("parseMarkdown", category: .rendering) {
///     parser.parse(input)
/// }
///
/// Signposts.event("scrollTick", category: .scroll)
/// ```
///
/// For intervals that need to attach metadata (input size, batch index, etc.), reach for the
/// underlying `OSSignposter` directly via `Signposts.signposter(for:)` so the signpost name
/// stays a `StaticString` and metadata is interpolated into an `OSLogMessage` (lazy when not
/// recording).
public enum Signposts {

    // MARK: - Per-category signposter instances

    /// Subsystem identifier for the rendering signposter. Exposed for documentation/testing.
    public static let renderingSubsystem = "place.wabash.VoidReader.rendering"
    public static let lifecycleSubsystem = "place.wabash.VoidReader.lifecycle"
    public static let scrollSubsystem = "place.wabash.VoidReader.scroll"
    public static let mermaidSubsystem = "place.wabash.VoidReader.mermaid"
    public static let imageSubsystem = "place.wabash.VoidReader.image"

    /// Signposter for the markdown rendering pipeline (`parseMarkdown`, `renderBatch`,
    /// `firstPaint`, `syntaxHighlightPass`).
    public static let rendering = OSSignposter(subsystem: renderingSubsystem, category: "rendering")

    /// Signposter for document lifecycle (`openDocument`, `closeDocument`, `reloadFromDisk`).
    public static let lifecycle = OSSignposter(subsystem: lifecycleSubsystem, category: "lifecycle")

    /// Signposter for scroll-loop signals (`scrollTick` event).
    public static let scroll = OSSignposter(subsystem: scrollSubsystem, category: "scroll")

    /// Signposter for mermaid diagram rendering (`mermaidRender`).
    public static let mermaid = OSSignposter(subsystem: mermaidSubsystem, category: "mermaid")

    /// Signposter for image loading (`imageLoad`).
    public static let image = OSSignposter(subsystem: imageSubsystem, category: "image")

    // MARK: - Convenience API

    /// Wrap a synchronous block in a named signpost interval.
    ///
    /// - Parameters:
    ///   - name: Stable name for the interval (must be a `StaticString` so `OSSignposter`
    ///     avoids per-call allocation).
    ///   - category: Subsystem the interval belongs to.
    ///   - block: The work being measured.
    /// - Returns: Whatever `block` returns.
    @inlinable
    public static func interval<T>(
        _ name: StaticString,
        category: SignpostCategory,
        _ block: () throws -> T
    ) rethrows -> T {
        let signposter = signposter(for: category)
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try block()
    }

    /// Wrap an async block in a named signpost interval.
    @inlinable
    public static func interval<T>(
        _ name: StaticString,
        category: SignpostCategory,
        _ block: () async throws -> T
    ) async rethrows -> T {
        let signposter = signposter(for: category)
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await block()
    }

    /// Emit a point-in-time signpost event. Prefer this over `interval` for hot loops where
    /// `begin`/`end` pairing overhead would matter (e.g., `scrollTick`).
    @inlinable
    public static func event(_ name: StaticString, category: SignpostCategory) {
        signposter(for: category).emitEvent(name)
    }

    /// Returns the underlying `OSSignposter` for a category. Use this when you need to attach
    /// metadata via `OSLogMessage` interpolation, e.g.:
    /// ```swift
    /// let signposter = Signposts.signposter(for: .rendering)
    /// let state = signposter.beginInterval("parseMarkdown", id: signposter.makeSignpostID(),
    ///                                       "bytes=\(input.utf8.count) nodes=\(nodeCount)")
    /// defer { signposter.endInterval("parseMarkdown", state) }
    /// ```
    @inlinable
    public static func signposter(for category: SignpostCategory) -> OSSignposter {
        switch category {
        case .rendering: return rendering
        case .lifecycle: return lifecycle
        case .scroll: return scroll
        case .mermaid: return mermaid
        case .image: return image
        }
    }
}

/// Subsystem buckets for VoidReader signposts. Each case maps to a distinct `OSSignposter`
/// with a stable subsystem identifier so Instruments filters remain reproducible across runs.
public enum SignpostCategory: String, CaseIterable, Sendable {
    case rendering
    case lifecycle
    case scroll
    case mermaid
    case image
}
