import SwiftUI
import VoidReaderCore

/// Renders a markdown table as a native SwiftUI grid.
struct TableBlockView: View {
    let data: TableData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(data.headers.enumerated()), id: \.element.id) { index, cell in
                    let alignment = index < data.alignments.count ? data.alignments[index] : .left

                    Text(cell.content)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment.horizontalAlignment, vertical: .center))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
                }
            }

            Divider()

            // Body rows
            ForEach(Array(data.rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { cellIndex, cell in
                        let alignment = cellIndex < data.alignments.count ? data.alignments[cellIndex] : .left

                        Text(cell.content)
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment.horizontalAlignment, vertical: .center))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(rowIndex % 2 == 1 ? Color(nsColor: .quaternaryLabelColor).opacity(0.2) : Color.clear)
                    }
                }

                if rowIndex < data.rows.count - 1 {
                    Divider()
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
