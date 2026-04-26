import SwiftUI
import VoidReaderCore

/// Renders YAML frontmatter as a compact metadata banner at the top of a document.
struct FrontmatterBannerView: View {
    let data: FrontmatterData

    /// Keys that get special rendering as inline pills.
    private static let tagKeys: Set<String> = ["tags", "categories", "keywords"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(data.fields.enumerated()), id: \.offset) { _, field in
                fieldRow(key: field.key, value: field.value)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func fieldRow(key: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key.lowercased())
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .frame(width: 70, alignment: .leading)

            if Self.tagKeys.contains(key.lowercased()) {
                tagPills(from: value)
                    .padding(.top, 1)
            } else {
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func tagPills(from value: String) -> some View {
        let tags = value
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                    )
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Simple flow layout for wrapping tag pills.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
            totalHeight = y + rowHeight
        }

        return ArrangeResult(
            size: CGSize(width: totalWidth, height: totalHeight),
            positions: positions
        )
    }
}

#Preview("Frontmatter Banner") {
    VStack(spacing: 20) {
        FrontmatterBannerView(data: FrontmatterData(fields: [
            (key: "title", value: "The Design of Everyday Things"),
            (key: "author", value: "Don Norman"),
            (key: "date", value: "2025-11-03"),
            (key: "tags", value: "design, ux, psychology, books"),
        ]))

        FrontmatterBannerView(data: FrontmatterData(fields: [
            (key: "layout", value: "post"),
            (key: "draft", value: "true"),
        ]))
    }
    .padding(40)
    .frame(width: 600)
}
