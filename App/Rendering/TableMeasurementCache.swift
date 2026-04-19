import AppKit
import Foundation
import SwiftUI
@preconcurrency import VoidReaderCore

/// Content-addressable cache key for a measured table. Scoped to the
/// presentation parameters that affect column width math — font metrics
/// (currently hard-coded to the system font at 14pt/semibold, but kept
/// explicit here so any future theming change forces a cache miss).
///
/// `tableID` is the `TableData.id` — a per-parse UUID. This means the
/// cache is document-lifetime: reparsing the document mints new IDs and
/// the prior entries become garbage. That's fine because the cache is
/// cleared on document change anyway.
struct TableMeasurementKey: Hashable {
    let tableID: UUID
    let bodyFontSize: CGFloat
    let headerFontSize: CGFloat
    let horizontalPadding: CGFloat
}

/// Outcome of measuring a table. Column widths are content-intrinsic — the
/// render path layers slack distribution on top once the container width
/// is known (we can't cache container width since the window resizes).
/// Row / header heights are determined by font metrics and vertical
/// padding, identical across every body row, so one value suffices.
struct TableMeasurementResult {
    /// Intrinsic column widths — the max rendered text width per column
    /// across header + body, *excluding* horizontal padding. The render
    /// path adds padding and slack.
    let columnWidths: [CGFloat]
    /// Height of the header row (bold font + its vertical padding).
    let headerHeight: CGFloat
    /// Height of a single body row (regular font + its vertical padding).
    /// Constant across all rows — we use `.frame(height:)` on each row so
    /// SwiftUI never has to run intrinsic-height queries during scroll.
    let rowHeight: CGFloat
}

/// Document-scoped, actor-isolated cache mapping `TableMeasurementKey` to
/// measured column widths. Lives for the lifetime of a document and is
/// cleared on document change. Mirrors `CodeBlockMeasurementCache`.
actor TableMeasurementCache {
    private var entries: [TableMeasurementKey: TableMeasurementResult] = [:]

    func get(_ key: TableMeasurementKey) -> TableMeasurementResult? {
        entries[key]
    }

    func set(_ key: TableMeasurementKey, result: TableMeasurementResult) {
        entries[key] = result
    }

    func clear() {
        entries.removeAll()
    }

    func contains(_ key: TableMeasurementKey) -> Bool {
        entries[key] != nil
    }
}

// MARK: - SwiftUI Environment

private struct TableMeasurementCacheKey: EnvironmentKey {
    static let defaultValue: TableMeasurementCache? = nil
}

extension EnvironmentValues {
    /// Document-scoped cache of column widths / row heights for tables.
    /// Set on the reader root via
    /// `.environment(\.tableMeasurementCache, cache)`.
    var tableMeasurementCache: TableMeasurementCache? {
        get { self[TableMeasurementCacheKey.self] }
        set { self[TableMeasurementCacheKey.self] = newValue }
    }
}

// MARK: - Measurement

/// Off-main measurement for tables. Produces the column widths that the
/// virtualized render path uses to lay each row's `HStack` out with fixed
/// cell widths — replacing SwiftUI `Grid`'s unified-column-width pass
/// (which forces the entire body to materialize even for a 12 500-row
/// table).
///
/// Runs on `TableMeasurementScheduler.queue` (a background queue) and
/// iterates every cell. For a 12 500-row × 5-column table that's 62 500
/// `NSAttributedString.size()` calls; at ~1 µs each that's ~60ms of
/// off-main work, well below the 3 s autoscroll start delay.
enum TableMeasurement {
    /// Padding that the render path adds around every cell. Baked into
    /// the key so any design change invalidates the cache automatically.
    static let horizontalPadding: CGFloat = 12
    static let bodyVerticalPadding: CGFloat = 6
    static let headerVerticalPadding: CGFloat = 8

    /// Body font used by the render path. Exposed for prefetch so the
    /// scheduler can reconstruct the same font off-main.
    static func bodyFont(size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .regular)
    }

    static func headerFont(size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    static func measure(
        data: TableData,
        bodyFont: NSFont,
        headerFont: NSFont
    ) -> TableMeasurementResult {
        let colCount = data.headers.count
        guard colCount > 0 else {
            return TableMeasurementResult(columnWidths: [], headerHeight: 0, rowHeight: 0)
        }

        var widths = [CGFloat](repeating: 0, count: colCount)

        // Headers (semibold).
        for (i, cell) in data.headers.enumerated() where i < colCount {
            let text = String(cell.content.characters)
            let attr = NSAttributedString(string: text, attributes: [.font: headerFont])
            let w = ceil(attr.size().width)
            if w > widths[i] { widths[i] = w }
        }

        // Body (regular). This is the hot loop — keeping the attribute
        // dict reusable and the string extraction tight keeps per-cell
        // cost near the NSAttributedString.size() floor.
        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont]
        for row in data.rows {
            for (i, cell) in row.enumerated() where i < colCount {
                let text = String(cell.content.characters)
                let attr = NSAttributedString(string: text, attributes: bodyAttrs)
                let w = ceil(attr.size().width)
                if w > widths[i] { widths[i] = w }
            }
        }

        let headerLineHeight = ceil(headerFont.ascender - headerFont.descender + headerFont.leading)
        let bodyLineHeight = ceil(bodyFont.ascender - bodyFont.descender + bodyFont.leading)

        return TableMeasurementResult(
            columnWidths: widths,
            headerHeight: headerLineHeight + headerVerticalPadding * 2,
            rowHeight: bodyLineHeight + bodyVerticalPadding * 2
        )
    }

    /// Distribute container slack across columns proportionally to their
    /// intrinsic widths — matches `Grid`'s observed behavior closely
    /// enough that columns don't visibly shift when the virtualized path
    /// takes over. When the table's intrinsic width already exceeds the
    /// container (narrow window), each column keeps its intrinsic width;
    /// the table horizontally overflows like `Grid` would.
    static func distributed(
        intrinsicWidths: [CGFloat],
        containerWidth: CGFloat,
        horizontalPadding: CGFloat
    ) -> [CGFloat] {
        let perCellPaddingOverhead = horizontalPadding * 2
        let colCount = intrinsicWidths.count
        guard colCount > 0 else { return [] }

        // Total width each column occupies on screen = intrinsic + padding.
        let paddedIntrinsic = intrinsicWidths.map { $0 + perCellPaddingOverhead }
        let sumPadded = paddedIntrinsic.reduce(0, +)
        let slack = containerWidth - sumPadded

        if slack <= 0 {
            return paddedIntrinsic
        }

        // Proportional slack — wider columns get more slack, narrower
        // columns stay proportionally narrow. Avoid divide-by-zero for
        // the (unrealistic) all-empty case.
        let sumIntrinsic = intrinsicWidths.reduce(0, +)
        if sumIntrinsic <= 0 {
            // All cells empty — distribute evenly.
            let share = slack / CGFloat(colCount)
            return paddedIntrinsic.map { $0 + share }
        }
        return zip(paddedIntrinsic, intrinsicWidths).map { padded, intrinsic in
            padded + slack * (intrinsic / sumIntrinsic)
        }
    }
}

/// Prefetch scheduler. Off-main measurement doesn't have the `Highlightr`
/// thread-affinity constraint that code blocks do, so this uses a
/// concurrent `DispatchQueue` — multiple tables can measure in parallel.
enum TableMeasurementScheduler {
    static let queue = DispatchQueue(
        label: "place.wabash.VoidReader.tableMeasurement",
        qos: .userInitiated,
        attributes: .concurrent
    )

    static func enqueueIfNeeded(
        data: TableData,
        bodyFontSize: CGFloat,
        headerFontSize: CGFloat,
        cache: TableMeasurementCache,
        onComplete: @escaping @MainActor (TableMeasurementKey, TableMeasurementResult) -> Void
    ) {
        let key = TableMeasurementKey(
            tableID: data.id,
            bodyFontSize: bodyFontSize,
            headerFontSize: headerFontSize,
            horizontalPadding: TableMeasurement.horizontalPadding
        )

        Task {
            if let existing = await cache.get(key) {
                await MainActor.run { onComplete(key, existing) }
                return
            }

            queue.async {
                let bodyFont = TableMeasurement.bodyFont(size: bodyFontSize)
                let headerFont = TableMeasurement.headerFont(size: headerFontSize)
                let result = TableMeasurement.measure(
                    data: data,
                    bodyFont: bodyFont,
                    headerFont: headerFont
                )
                Task {
                    await cache.set(key, result: result)
                    await MainActor.run { onComplete(key, result) }
                }
            }
        }
    }
}
