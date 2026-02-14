import SwiftUI

/// A find bar for searching document content, with optional replace functionality.
struct FindBarView: View {
    @Binding var isVisible: Bool
    @Binding var searchText: String
    @Binding var replaceText: String
    let matchCount: Int
    let currentMatch: Int
    let isEditMode: Bool
    let showReplace: Bool
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedField: Field?

    enum Field {
        case search, replace
    }

    var body: some View {
        VStack(spacing: 6) {
            // Find row
            HStack(spacing: 8) {
                // Search field
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))

                    TextField("Find in document", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focusedField, equals: .search)
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

            // Replace row (only in edit mode with showReplace)
            if isEditMode && showReplace {
                HStack(spacing: 8) {
                    // Replace field
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))

                        TextField("Replace with", text: $replaceText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .focused($focusedField, equals: .replace)
                            .onSubmit {
                                onReplace()
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

                    // Replace buttons
                    Button("Replace") {
                        onReplace()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .disabled(matchCount == 0)

                    Button("Replace All") {
                        onReplaceAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .disabled(matchCount == 0)

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            focusedField = .search
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

#Preview("Find Only") {
    VStack {
        FindBarView(
            isVisible: .constant(true),
            searchText: .constant("test"),
            replaceText: .constant(""),
            matchCount: 12,
            currentMatch: 3,
            isEditMode: false,
            showReplace: false,
            onNext: {},
            onPrevious: {},
            onReplace: {},
            onReplaceAll: {},
            onDismiss: {}
        )
        Spacer()
    }
    .frame(width: 600, height: 100)
}

#Preview("Find & Replace") {
    VStack {
        FindBarView(
            isVisible: .constant(true),
            searchText: .constant("test"),
            replaceText: .constant("replacement"),
            matchCount: 12,
            currentMatch: 3,
            isEditMode: true,
            showReplace: true,
            onNext: {},
            onPrevious: {},
            onReplace: {},
            onReplaceAll: {},
            onDismiss: {}
        )
        Spacer()
    }
    .frame(width: 600, height: 120)
}
