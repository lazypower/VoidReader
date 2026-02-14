import SwiftUI

/// A find bar for searching document content.
struct FindBarView: View {
    @Binding var isVisible: Bool
    @Binding var searchText: String
    let matchCount: Int
    let currentMatch: Int
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                TextField("Find in document", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .onSubmit {
                        onNext()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .frame(width: 220)

            // Match count
            if !searchText.isEmpty {
                Text(matchCountText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 60)
            }

            // Navigation buttons
            HStack(spacing: 2) {
                Button {
                    onPrevious()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(matchCount == 0)
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button {
                    onNext()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
                .disabled(matchCount == 0)
                .keyboardShortcut("g", modifiers: .command)
            }

            Spacer()

            // Done button
            Button("Done") {
                onDismiss()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isFocused = true
        }
    }

    private var matchCountText: String {
        if matchCount == 0 {
            return "No matches"
        } else if matchCount == 1 {
            return "1 match"
        } else {
            return "\(currentMatch) of \(matchCount)"
        }
    }
}

#Preview {
    VStack {
        FindBarView(
            isVisible: .constant(true),
            searchText: .constant("test"),
            matchCount: 12,
            currentMatch: 3,
            onNext: {},
            onPrevious: {},
            onDismiss: {}
        )
        Spacer()
    }
    .frame(width: 600, height: 100)
}
