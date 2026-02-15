import SwiftUI
import VoidReaderCore

/// Displays a hierarchical outline of document headings.
struct OutlineSidebarView: View {
    let headings: [HeadingInfo]
    let onHeadingTap: (HeadingInfo) -> Void
    var currentHeadingID: UUID?

    @State private var selectedIndex: Int?
    @FocusState private var isFocused: Bool

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
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(headings.enumerated()), id: \.element.id) { index, heading in
                                OutlineRow(
                                    heading: heading,
                                    isCurrentSection: heading.id == currentHeadingID,
                                    isKeyboardSelected: isFocused && selectedIndex == index,
                                    onTap: {
                                        selectedIndex = index
                                        onHeadingTap(heading)
                                    }
                                )
                                .id(index)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        if let index = newIndex {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                proxy.scrollTo(index, anchor: .center)
                            }
                        }
                    }
                }
                .focusable()
                .focused($isFocused)
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.return) {
                    if let index = selectedIndex, index < headings.count {
                        onHeadingTap(headings[index])
                    }
                    return .handled
                }
            }
        }
        .frame(width: 220)
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: currentHeadingID) { _, newID in
            // Sync keyboard selection with scroll-based current heading
            if let id = newID, let index = headings.firstIndex(where: { $0.id == id }) {
                selectedIndex = index
            }
        }
    }

    private func moveSelection(by offset: Int) {
        guard !headings.isEmpty else { return }

        if let current = selectedIndex {
            let newIndex = max(0, min(headings.count - 1, current + offset))
            selectedIndex = newIndex
        } else {
            // No selection yet, start at beginning or end
            selectedIndex = offset > 0 ? 0 : headings.count - 1
        }
    }
}

/// A single row in the outline sidebar.
private struct OutlineRow: View {
    let heading: HeadingInfo
    let isCurrentSection: Bool
    var isKeyboardSelected: Bool = false
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
            .background(backgroundColor)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isKeyboardSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var backgroundColor: Color {
        if isKeyboardSelected {
            return Color.accentColor.opacity(0.2)
        } else if isCurrentSection {
            return Color.accentColor.opacity(0.1)
        }
        return Color.clear
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
