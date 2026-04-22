import SwiftUI
import VoidReaderCore

/// Renders a markdown table.
///
/// ## Two rendering paths
///
/// - **Small tables** (≤ `virtualizationThreshold` rows): SwiftUI `Grid`.
///   Simple, works well, no measurement latency. `Grid`'s unified
///   column-width pass forces the whole body to materialize, which is
///   O(rows × cols) — fine below a few dozen rows.
/// - **Large tables**: virtualized path. Column widths are measured
///   once off-main (`TableMeasurementScheduler`), then the body is
///   rendered as a `LazyVStack` of `HStack` rows with fixed-width cells.
///   Only the visible rows materialize, and since every cell has a
///   fixed frame the renderer never runs intrinsic-size queries during
///   scroll. Collapses per-frame layout work from O(rows × cols) to
///   O(visible rows), which is the fix for the main-thread saturation
///   that `Grid` produces on large tables (50% of scroll samples in
///   `AG::Graph/Subgraph/CA::Transaction` with 12 500 rows).
///
/// ## Why the Grid path stays
/// The virtualized path needs a measurement window — even if we run it
/// off-main, the first paint is necessarily a placeholder until the
/// widths land. That's a fine trade for a 12 500-row table, a bad trade
/// for a 4-row one. The threshold is the crossover; keep `Grid` below it.
struct TableBlockView: View {
    /// Rows at or above this count route through the virtualized path.
    /// 50 is conservative — every table above that benefits measurably,
    /// and the measurement window stays under a frame (~16ms) at this size.
    static let virtualizationThreshold = 50

    let data: TableData

    @Environment(\.tableMeasurementCache) private var measurementCache
    @State private var measurement: TableMeasurementResult?

    private static let bodyFontSize: CGFloat = 14
    private static let headerFontSize: CGFloat = 14

    private var useVirtualized: Bool {
        data.rows.count >= Self.virtualizationThreshold
    }

    var body: some View {
        if useVirtualized {
            virtualizedBody
                .onAppear(perform: requestMeasurement)
        } else {
            gridBody
        }
    }

    // MARK: - Grid path (small tables)

    private var gridBody: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(data.headers.enumerated()), id: \.element.id) { index, cell in
                    let alignment = index < data.alignments.count ? data.alignments[index] : .left

                    Text(cell.content)
                        .font(.system(size: Self.headerFontSize, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment.horizontalAlignment, vertical: .center))
                        .padding(.horizontal, TableMeasurement.horizontalPadding)
                        .padding(.vertical, TableMeasurement.headerVerticalPadding)
                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                }
            }

            Divider()

            ForEach(Array(data.rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.element.id) { cellIndex, cell in
                        let alignment = cellIndex < data.alignments.count ? data.alignments[cellIndex] : .left

                        Text(cell.content)
                            .font(.system(size: Self.bodyFontSize))
                            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment.horizontalAlignment, vertical: .center))
                            .padding(.horizontal, TableMeasurement.horizontalPadding)
                            .padding(.vertical, TableMeasurement.bodyVerticalPadding)
                            .background(rowIndex % 2 == 1 ? Color(nsColor: .quaternaryLabelColor).opacity(0.2) : Color.clear)
                    }
                }

                if rowIndex < data.rows.count - 1 {
                    Divider()
                        .gridCellUnsizedAxes(.horizontal)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Virtualized path (large tables)

    /// Outer frame — captures container width so column-slack
    /// distribution produces the same widths `Grid` would. Wraps the
    /// body in the same rounded / bordered container as the Grid path,
    /// so large and small tables present identically.
    private var virtualizedBody: some View {
        GeometryReader { geo in
            virtualizedContent(containerWidth: geo.size.width)
        }
        .frame(height: placeholderTotalHeight)
    }

    @ViewBuilder
    private func virtualizedContent(containerWidth: CGFloat) -> some View {
        if let measurement {
            let widths = TableMeasurement.distributed(
                intrinsicWidths: measurement.columnWidths,
                containerWidth: containerWidth,
                horizontalPadding: TableMeasurement.horizontalPadding
            )
            renderedTable(widths: widths, measurement: measurement)
        } else {
            // Placeholder at the authoritative total height — scroll
            // position is stable across the measurement swap because
            // row count × row height is deterministic from font metrics.
            Color.clear
        }
    }

    private func renderedTable(widths: [CGFloat], measurement: TableMeasurementResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow(widths: widths, height: measurement.headerHeight)
            Divider()

            LazyVStack(alignment: .leading, spacing: 0) {
                // Use row index as identity. Rows are structurally
                // identical and never reordered, so index-based identity
                // is stable and cheap (no UUID hashing per row).
                ForEach(0..<data.rows.count, id: \.self) { rowIndex in
                    bodyRow(
                        rowIndex: rowIndex,
                        widths: widths,
                        height: measurement.rowHeight
                    )
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func headerRow(widths: [CGFloat], height: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(data.headers.enumerated()), id: \.element.id) { index, cell in
                let alignment = index < data.alignments.count ? data.alignments[index] : .left
                let width = index < widths.count ? widths[index] : 0

                Text(cell.content)
                    .font(.system(size: Self.headerFontSize, weight: .semibold))
                    .frame(width: width, alignment: Alignment(horizontal: alignment.horizontalAlignment, vertical: .center))
                    .padding(.vertical, TableMeasurement.headerVerticalPadding)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
    }

    @ViewBuilder
    private func bodyRow(rowIndex: Int, widths: [CGFloat], height: CGFloat) -> some View {
        let row = data.rows[rowIndex]
        let isLast = rowIndex == data.rows.count - 1

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(row.enumerated()), id: \.element.id) { cellIndex, cell in
                    let alignment = cellIndex < data.alignments.count ? data.alignments[cellIndex] : .left
                    let width = cellIndex < widths.count ? widths[cellIndex] : 0

                    Text(cell.content)
                        .font(.system(size: Self.bodyFontSize))
                        .frame(width: width, alignment: Alignment(horizontal: alignment.horizontalAlignment, vertical: .center))
                        .padding(.vertical, TableMeasurement.bodyVerticalPadding)
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowIndex % 2 == 1 ? Color(nsColor: .quaternaryLabelColor).opacity(0.2) : Color.clear)

            if !isLast {
                Divider()
            }
        }
    }

    // MARK: - Measurement

    private func requestMeasurement() {
        guard measurement == nil, let cache = measurementCache else { return }

        TableMeasurementScheduler.enqueueIfNeeded(
            data: data,
            bodyFontSize: Self.bodyFontSize,
            headerFontSize: Self.headerFontSize,
            cache: cache
        ) { _, result in
            measurement = result
        }
    }

    /// Deterministic placeholder total height. Matches exactly what the
    /// measured path will produce (row heights are font-metric-derived,
    /// not content-derived), so scroll position stays pinned across the
    /// measurement swap. The `+ 1` fudge per divider mirrors the 1pt
    /// `Divider` between header/body and between body rows.
    private var placeholderTotalHeight: CGFloat {
        let headerFont = TableMeasurement.headerFont(size: Self.headerFontSize)
        let bodyFont = TableMeasurement.bodyFont(size: Self.bodyFontSize)
        let headerH = ceil(headerFont.ascender - headerFont.descender + headerFont.leading)
            + TableMeasurement.headerVerticalPadding * 2
        let rowH = ceil(bodyFont.ascender - bodyFont.descender + bodyFont.leading)
            + TableMeasurement.bodyVerticalPadding * 2
        let dividerCount = max(0, data.rows.count)  // 1 between header/body + (rows-1) between rows
        return headerH + rowH * CGFloat(data.rows.count) + CGFloat(dividerCount)
    }
}

#Preview {
    let sampleTable = TableData(
        headers: [
            TableCell(content: AttributedString("Feature")),
            TableCell(content: AttributedString("Status")),
            TableCell(content: AttributedString("Notes"))
        ],
        rows: [
            [
                TableCell(content: AttributedString("Tables")),
                TableCell(content: AttributedString("Done")),
                TableCell(content: AttributedString("Looking good"))
            ],
            [
                TableCell(content: AttributedString("Task Lists")),
                TableCell(content: AttributedString("In Progress")),
                TableCell(content: AttributedString("Almost there"))
            ]
        ],
        alignments: [.left, .center, .left]
    )

    return TableBlockView(data: sampleTable)
        .padding()
        .frame(width: 500)
}
