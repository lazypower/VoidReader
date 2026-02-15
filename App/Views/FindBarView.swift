import SwiftUI

/// A find bar for searching document content, with optional replace functionality.
struct FindBarView: View {
    @Binding var isVisible: Bool
    @Binding var searchText: String
    @Binding var replaceText: String
    @Binding var caseSensitive: Bool
    @Binding var useRegex: Bool
    let matchCount: Int
    let currentMatch: Int
    let currentMatchText: String?
    let isEditMode: Bool
    let showReplace: Bool
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
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

                // Search options
                HStack(spacing: 4) {
                    Toggle(isOn: $caseSensitive) {
                        Text("Aa")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .help("Case Sensitive")

                    Toggle(isOn: $useRegex) {
                        Text(".*")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.borderless)
                    .help("Regular Expression")
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

                    // Replacement preview
                    if let matchText = currentMatchText, matchCount > 0 {
                        HStack(spacing: 4) {
                            Text(matchText)
                                .strikethrough()
                                .foregroundColor(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(replaceText.isEmpty ? "(empty)" : replaceText)
                                .foregroundColor(replaceText.isEmpty ? .secondary : .primary)
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)
                        .lineLimit(1)
                    }

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
        .onKeyPress(.tab) {
            // Tab cycles between search and replace fields
            if showReplace && isEditMode {
                if focusedField == .search {
                    focusedField = .replace
                } else {
                    focusedField = .search
                }
                return .handled
            }
            return .ignored
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
            caseSensitive: .constant(false),
            useRegex: .constant(false),
            matchCount: 12,
            currentMatch: 3,
            currentMatchText: nil,
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
            caseSensitive: .constant(true),
            useRegex: .constant(false),
            matchCount: 12,
            currentMatch: 3,
            currentMatchText: "test",
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
    .frame(width: 700, height: 120)
}
