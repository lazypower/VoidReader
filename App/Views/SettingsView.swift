import SwiftUI
import AppKit
import VoidReaderCore

/// Settings window for VoidReader preferences.
struct SettingsView: View {
    @AppStorage("selectedThemeID") private var selectedThemeID: String = "system"
    @AppStorage("appearanceOverride") private var appearanceOverride: String = "system"
    @AppStorage("readerFontFamily") private var readerFontFamily: String = ""
    @AppStorage("readerFontSize") private var readerFontSize: Double = 16.0
    @AppStorage("codeFontFamily") private var codeFontFamily: String = ""

    // Formatting settings
    @AppStorage("formatOnSave") private var formatOnSave: Bool = false
    @AppStorage("listMarkerStyle") private var listMarkerStyle: String = "-"
    @AppStorage("emphasisMarkerStyle") private var emphasisMarkerStyle: String = "*"
    @AppStorage("disabledLintRules") private var disabledLintRules: String = ""

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Form {
            // MARK: - Appearance Section
            Section {
                // Theme picker
                Picker("Theme", selection: $selectedThemeID) {
                    ForEach(ThemeRegistry.shared.themes) { theme in
                        HStack(spacing: 8) {
                            ThemePreviewSwatch(theme: theme, colorScheme: effectiveColorScheme)
                            Text(theme.displayName)
                        }
                        .tag(theme.id)
                    }
                }
                .pickerStyle(.menu)

                // Appearance override
                Picker("Appearance", selection: $appearanceOverride) {
                    Text("System").tag("system")
                    Text("Always Light").tag("light")
                    Text("Always Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            }

            // MARK: - Reader Section
            Section {
                LabeledContent("Reader Font") {
                    FontPickerButton(
                        fontFamily: $readerFontFamily,
                        fontSize: $readerFontSize,
                        monospacedOnly: false
                    )
                }

                LabeledContent("Font Size") {
                    HStack {
                        Slider(value: $readerFontSize, in: 10...32, step: 1)
                            .frame(width: 150)
                        Text("\(Int(readerFontSize)) pt")
                            .frame(width: 45, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Reader")
            }

            Section {
                LabeledContent("Code Font") {
                    FontPickerButton(
                        fontFamily: $codeFontFamily,
                        fontSize: .constant(13),
                        monospacedOnly: true
                    )
                }
            } header: {
                Text("Code Blocks")
            }

            // MARK: - Formatting Section
            Section {
                Toggle("Format on Save", isOn: $formatOnSave)

                Picker("List Markers", selection: $listMarkerStyle) {
                    ForEach(FormatterOptions.ListMarkerStyle.allCases) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Picker("Emphasis Markers", selection: $emphasisMarkerStyle) {
                    ForEach(FormatterOptions.EmphasisMarkerStyle.allCases) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Formatting")
            } footer: {
                Text("Format on Save normalizes list markers, removes trailing whitespace, and collapses multiple blank lines.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // MARK: - Lint Rules Section
            Section {
                ForEach(MarkdownLinter.allRules, id: \.id) { rule in
                    Toggle(isOn: lintRuleBinding(for: rule.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.id)
                                .font(.body.monospaced())
                            Text(rule.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Lint Rules")
            } footer: {
                Text("Disabled rules will not show warnings in the editor.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Text("Use **Cmd +/-** to quickly adjust font size")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Use **Cmd 0** to reset to default size")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Tips")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 450, idealWidth: 500, minHeight: 500, idealHeight: 600)
    }

    /// Effective color scheme based on override setting
    private var effectiveColorScheme: ColorScheme {
        switch appearanceOverride {
        case "light": return .light
        case "dark": return .dark
        default: return colorScheme
        }
    }

    /// Creates a binding for a lint rule's enabled state.
    private func lintRuleBinding(for ruleID: String) -> Binding<Bool> {
        Binding(
            get: {
                let disabled = Set(disabledLintRules.split(separator: ",").map(String.init))
                return !disabled.contains(ruleID)
            },
            set: { isEnabled in
                var disabled = Set(disabledLintRules.split(separator: ",").map(String.init))
                if isEnabled {
                    disabled.remove(ruleID)
                } else {
                    disabled.insert(ruleID)
                }
                disabledLintRules = disabled.sorted().joined(separator: ",")
            }
        )
    }
}

/// Small color swatch preview for theme picker
struct ThemePreviewSwatch: View {
    let theme: AppTheme
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 2) {
            let palette = theme.palette(for: colorScheme)
            Circle().fill(palette.mauve).frame(width: 10, height: 10)
            Circle().fill(palette.blue).frame(width: 10, height: 10)
            Circle().fill(palette.green).frame(width: 10, height: 10)
            Circle().fill(palette.teal).frame(width: 10, height: 10)
        }
    }
}

/// A button that opens the native macOS font picker.
struct FontPickerButton: View {
    @Binding var fontFamily: String
    @Binding var fontSize: Double
    let monospacedOnly: Bool

    @State private var showingFontPanel = false

    var displayName: String {
        if fontFamily.isEmpty {
            return monospacedOnly ? "System Mono" : "System"
        }
        // Get display name from font family
        if let font = NSFont(name: fontFamily, size: 12) {
            return font.displayName ?? fontFamily
        }
        return fontFamily
    }

    var body: some View {
        Button(action: { showFontPanel() }) {
            HStack {
                Text(displayName)
                    .font(previewFont)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 180, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var previewFont: Font {
        if fontFamily.isEmpty {
            return monospacedOnly ? .system(size: 13, design: .monospaced) : .system(size: 13)
        }
        return .custom(fontFamily, size: 13)
    }

    private func showFontPanel() {
        let fontManager = NSFontManager.shared
        let fontPanel = NSFontPanel.shared

        // Set current font
        let currentFont: NSFont
        if fontFamily.isEmpty {
            currentFont = monospacedOnly
                ? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
                : NSFont.systemFont(ofSize: CGFloat(fontSize))
        } else {
            currentFont = NSFont(name: fontFamily, size: CGFloat(fontSize))
                ?? NSFont.systemFont(ofSize: CGFloat(fontSize))
        }

        fontManager.setSelectedFont(currentFont, isMultiple: false)

        // Set up target for font changes
        fontManager.target = FontPanelDelegate.shared
        FontPanelDelegate.shared.onFontChange = { newFont in
            fontFamily = newFont.familyName ?? ""
            fontSize = Double(newFont.pointSize)
        }

        // Show the panel
        fontPanel.orderFront(nil)
        fontPanel.makeKey()
    }
}

/// Delegate to receive font panel changes.
private class FontPanelDelegate: NSObject {
    static let shared = FontPanelDelegate()

    var onFontChange: ((NSFont) -> Void)?

    @objc func changeFont(_ sender: NSFontManager?) {
        guard let fontManager = sender else { return }
        let newFont = fontManager.convert(.systemFont(ofSize: 13))
        onFontChange?(newFont)
    }
}

#Preview {
    SettingsView()
}
