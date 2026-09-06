import AppKit
import SwiftUI
import VoidReaderCore

/// A single native drawing surface for large, read-only tables. SwiftUI's
/// LazyVStack limits retained rows, but each newly visible row still builds a
/// deep tree of Text/HStack/VStack/Divider nodes. This view draws only the
/// rows intersecting AppKit's dirty rectangle while preserving the measured
/// column widths and the small-table visual language.
struct LargeTableView: NSViewRepresentable {
    let data: TableData
    let widths: [CGFloat]
    let measurement: TableMeasurementResult

    func makeNSView(context: Context) -> LargeTableCanvas {
        LargeTableCanvas(data: data, widths: widths, measurement: measurement)
    }

    func updateNSView(_ view: LargeTableCanvas, context: Context) {
        view.update(data: data, widths: widths, measurement: measurement)
    }
}

final class LargeTableCanvas: NSView {
    private var data: TableData
    private var widths: [CGFloat]
    private var measurement: TableMeasurementResult

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    init(data: TableData, widths: [CGFloat], measurement: TableMeasurementResult) {
        self.data = data
        self.widths = widths
        self.measurement = measurement
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.table)
        updateAccessibilityDescription()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(data: TableData, widths: [CGFloat], measurement: TableMeasurementResult) {
        self.data = data
        self.widths = widths
        self.measurement = measurement
        updateAccessibilityDescription()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let background = NSColor.textBackgroundColor
        background.setFill()
        dirtyRect.fill()

        drawHeader(in: dirtyRect)
        drawVisibleRows(in: dirtyRect)
        drawRoundedCorners(in: dirtyRect, background: background)
        drawBorder(in: dirtyRect)
    }

    private func drawHeader(in dirtyRect: NSRect) {
        let headerRect = NSRect(x: 0, y: 0, width: bounds.width, height: measurement.headerHeight)
        guard headerRect.intersects(dirtyRect) else { return }

        semanticFillColor(.quaternaryLabelColor, opacity: 0.5).setFill()
        headerRect.fill()
        draw(cells: data.headers, in: headerRect, font: TableMeasurement.headerFont(size: 14))
        drawSeparator(y: headerRect.maxY)
    }

    private func drawVisibleRows(in dirtyRect: NSRect) {
        guard !data.rows.isEmpty else { return }

        let firstRowY = measurement.headerHeight + 1
        let stride = measurement.rowHeight + 1
        let first = max(0, Int(floor((dirtyRect.minY - firstRowY) / stride)))
        let last = min(
            data.rows.count - 1,
            Int(ceil((dirtyRect.maxY - firstRowY) / stride))
        )
        guard first <= last else { return }

        let font = TableMeasurement.bodyFont(size: 14)
        for rowIndex in first...last {
            let y = firstRowY + CGFloat(rowIndex) * stride
            let rowRect = NSRect(x: 0, y: y, width: bounds.width, height: measurement.rowHeight)

            if rowIndex.isMultiple(of: 2) == false {
                semanticFillColor(.quaternaryLabelColor, opacity: 0.2).setFill()
                rowRect.fill()
            }

            draw(cells: data.rows[rowIndex], in: rowRect, font: font)
            if rowIndex < data.rows.count - 1 {
                drawSeparator(y: rowRect.maxY)
            }
        }
    }

    private func draw(cells: [TableCell], in rowRect: NSRect, font: NSFont) {
        var x: CGFloat = 0
        let lineHeight = ceil(font.ascender - font.descender + font.leading)

        for (index, cell) in cells.enumerated() where index < widths.count {
            let width = widths[index]
            let alignment = index < data.alignments.count ? data.alignments[index] : .left
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment.nsTextAlignment
            paragraph.lineBreakMode = .byTruncatingTail

            let textRect = NSRect(
                x: x + TableMeasurement.horizontalPadding,
                y: rowRect.minY + max(0, (rowRect.height - lineHeight) / 2),
                width: max(0, width - TableMeasurement.horizontalPadding * 2),
                height: lineHeight
            )
            let baseAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]

            if let plainText = cell.plainText {
                (plainText as NSString).draw(in: textRect, withAttributes: baseAttributes)
            } else {
                let richText = NSMutableAttributedString(attributedString: NSAttributedString(cell.content))
                richText.addAttributes(baseAttributes, range: NSRange(location: 0, length: richText.length))
                richText.draw(in: textRect)
            }
            x += width
        }
    }

    private func drawSeparator(y: CGFloat) {
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
    }

    private func drawBorder(in dirtyRect: NSRect) {
        let radius: CGFloat = 6
        NSColor.separatorColor.setStroke()

        // During normal scrolling only draw the two visible vertical edge
        // fragments. Stroking one path as tall as a 50K-row table made Core
        // Graphics process a 1.5-million-point segment on every dirty row.
        let sideMinY = max(radius, dirtyRect.minY)
        let sideMaxY = min(bounds.height - radius, dirtyRect.maxY)
        if sideMinY < sideMaxY {
            let sides = NSBezierPath()
            sides.lineWidth = 1
            sides.move(to: NSPoint(x: 0.5, y: sideMinY))
            sides.line(to: NSPoint(x: 0.5, y: sideMaxY))
            sides.move(to: NSPoint(x: bounds.width - 0.5, y: sideMinY))
            sides.line(to: NSPoint(x: bounds.width - 0.5, y: sideMaxY))
            sides.stroke()
        }

        if dirtyRect.minY < radius {
            roundedHorizontalBorder(y: 0.5, radius: radius, top: true).stroke()
        }
        if dirtyRect.maxY > bounds.height - radius {
            roundedHorizontalBorder(y: bounds.height - 0.5, radius: radius, top: false).stroke()
        }
    }

    private func roundedHorizontalBorder(y: CGFloat, radius: CGFloat, top: Bool) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = 1
        let edgeY = top ? radius : bounds.height - radius
        let control = radius * 0.552_284_75

        path.move(to: NSPoint(x: 0.5, y: edgeY))
        path.curve(
            to: NSPoint(x: radius, y: y),
            controlPoint1: NSPoint(x: 0.5, y: top ? edgeY - control : edgeY + control),
            controlPoint2: NSPoint(x: radius - control, y: y)
        )
        path.line(to: NSPoint(x: bounds.width - radius, y: y))
        path.curve(
            to: NSPoint(x: bounds.width - 0.5, y: edgeY),
            controlPoint1: NSPoint(x: bounds.width - radius + control, y: y),
            controlPoint2: NSPoint(x: bounds.width - 0.5, y: top ? edgeY - control : edgeY + control)
        )
        return path
    }

    /// Carve the header/last-row fills back to the reader background at the
    /// four outer corners. These tiny local paths reproduce clipping without
    /// applying a mask to a view that may be millions of points tall.
    private func drawRoundedCorners(in dirtyRect: NSRect, background: NSColor) {
        let radius: CGFloat = 6
        let control = radius * 0.552_284_75
        background.setFill()

        if dirtyRect.minY < radius {
            cornerPath(
                points: [
                    NSPoint(x: 0, y: 0), NSPoint(x: radius, y: 0),
                    NSPoint(x: 0, y: radius),
                ],
                control1: NSPoint(x: radius - control, y: 0),
                control2: NSPoint(x: 0, y: radius - control)
            ).fill()
            cornerPath(
                points: [
                    NSPoint(x: bounds.width, y: 0), NSPoint(x: bounds.width - radius, y: 0),
                    NSPoint(x: bounds.width, y: radius),
                ],
                control1: NSPoint(x: bounds.width - radius + control, y: 0),
                control2: NSPoint(x: bounds.width, y: radius - control)
            ).fill()
        }

        if dirtyRect.maxY > bounds.height - radius {
            cornerPath(
                points: [
                    NSPoint(x: 0, y: bounds.height), NSPoint(x: radius, y: bounds.height),
                    NSPoint(x: 0, y: bounds.height - radius),
                ],
                control1: NSPoint(x: radius - control, y: bounds.height),
                control2: NSPoint(x: 0, y: bounds.height - radius + control)
            ).fill()
            cornerPath(
                points: [
                    NSPoint(x: bounds.width, y: bounds.height), NSPoint(x: bounds.width - radius, y: bounds.height),
                    NSPoint(x: bounds.width, y: bounds.height - radius),
                ],
                control1: NSPoint(x: bounds.width - radius + control, y: bounds.height),
                control2: NSPoint(x: bounds.width, y: bounds.height - radius + control)
            ).fill()
        }
    }

    private func cornerPath(
        points: [NSPoint],
        control1: NSPoint,
        control2: NSPoint
    ) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: points[0])
        path.line(to: points[1])
        path.curve(to: points[2], controlPoint1: control1, controlPoint2: control2)
        path.close()
        return path
    }

    /// SwiftUI's `.opacity` multiplies a semantic color's existing alpha.
    /// `NSColor.withAlphaComponent`, by contrast, replaces it. Quaternary
    /// label colors are already translucent, so replacement made the native
    /// canvas header and stripes several times darker than the Grid version.
    private func semanticFillColor(_ color: NSColor, opacity: CGFloat) -> NSColor {
        color.withAlphaComponent(color.alphaComponent * opacity)
    }

    private func updateAccessibilityDescription() {
        setAccessibilityLabel("Table")
        setAccessibilityHelp("\(data.rows.count) rows, \(data.headers.count) columns")
    }
}

private extension TableAlignment {
    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }
}
