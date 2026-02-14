import SwiftUI
import VoidReaderCore

/// Status bar displaying document statistics.
struct StatusBarView: View {
    let stats: DocumentStats
    var selectionStats: DocumentStats?

    var body: some View {
        HStack(spacing: 16) {
            // Word count
            statItem(
                icon: "text.word.spacing",
                value: displayStats.wordCountFormatted
            )

            Divider()
                .frame(height: 12)

            // Character count
            statItem(
                icon: "character",
                value: displayStats.characterCountFormatted
            )

            Divider()
                .frame(height: 12)

            // Reading time
            statItem(
                icon: "clock",
                value: displayStats.readingTimeFormatted
            )

            Spacer()

            // Selection indicator
            if selectionStats != nil {
                Text("Selection")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .top
        )
    }

    private var displayStats: DocumentStats {
        selectionStats ?? stats
    }

    private func statItem(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(value)
        }
    }
}

#Preview("Document Stats") {
    VStack {
        Spacer()
        StatusBarView(
            stats: DocumentStats(text: "Hello world, this is a sample document with some words to count.")
        )
    }
    .frame(width: 500, height: 100)
}

#Preview("With Selection") {
    VStack {
        Spacer()
        StatusBarView(
            stats: DocumentStats(text: "Hello world, this is a sample document with some words to count."),
            selectionStats: DocumentStats(text: "sample document")
        )
    }
    .frame(width: 500, height: 100)
}
