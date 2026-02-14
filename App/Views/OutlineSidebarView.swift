import SwiftUI
import VoidReaderCore

/// Displays a hierarchical outline of document headings.
struct OutlineSidebarView: View {
    let headings: [HeadingInfo]
    let onHeadingTap: (HeadingInfo) -> Void
    var currentHeadingID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Outline")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if headings.isEmpty {
                VStack {
                    Spacer()
                    Text("No headings")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(headings) { heading in
                            OutlineRow(
                                heading: heading,
                                isCurrentSection: heading.id == currentHeadingID,
                                onTap: { onHeadingTap(heading) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 220)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// A single row in the outline sidebar.
private struct OutlineRow: View {
    let heading: HeadingInfo
    let isCurrentSection: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                // Indentation based on heading level
                Text(heading.text)
                    .font(fontForLevel(heading.level))
                    .foregroundColor(isCurrentSection ? .accentColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.leading, indentForLevel(heading.level))
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(isCurrentSection ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func indentForLevel(_ level: Int) -> CGFloat {
        CGFloat((level - 1) * 12) + 4
    }

    private func fontForLevel(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 13, weight: .semibold)
        case 2: return .system(size: 12, weight: .medium)
        default: return .system(size: 11, weight: .regular)
        }
    }
}

#Preview {
    OutlineSidebarView(
        headings: [
            HeadingInfo(level: 1, text: "Introduction"),
            HeadingInfo(level: 2, text: "Getting Started"),
            HeadingInfo(level: 3, text: "Installation"),
            HeadingInfo(level: 3, text: "Configuration"),
            HeadingInfo(level: 2, text: "Usage"),
            HeadingInfo(level: 1, text: "API Reference"),
            HeadingInfo(level: 2, text: "Methods"),
        ],
        onHeadingTap: { _ in },
        currentHeadingID: nil
    )
    .frame(height: 400)
}
