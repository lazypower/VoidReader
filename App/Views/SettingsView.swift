import SwiftUI
import AppKit

/// Settings window for VoidReader preferences.
struct SettingsView: View {
    @AppStorage("readerFontFamily") private var readerFontFamily: String = ""
    @AppStorage("readerFontSize") private var readerFontSize: Double = 16.0
    @AppStorage("codeFontFamily") private var codeFontFamily: String = ""

    var body: some View {
        Form {
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
        .frame(minWidth: 450, idealWidth: 500, minHeight: 320, idealHeight: 360)
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
