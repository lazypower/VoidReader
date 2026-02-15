import Foundation
import SwiftUI

/// Loads user themes from the application support directory.
public struct ThemeLoader {

    /// Standard location for user themes
    public static var themesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoidReader/themes", isDirectory: true)
    }

    /// Ensures the themes directory exists, creating it if necessary.
    public static func ensureThemesDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: themesDirectory.path) {
            try? fm.createDirectory(at: themesDirectory, withIntermediateDirectories: true)
        }
    }

    /// Loads all valid theme files from the themes directory.
    /// Invalid themes are skipped with a warning logged.
    public static func loadUserThemes() -> [AppTheme] {
        ensureThemesDirectoryExists()

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: themesDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        var themes: [AppTheme] = []

        for file in files where file.pathExtension == "json" {
            do {
                let theme = try loadTheme(from: file)
                themes.append(theme)
            } catch {
                print("Warning: Failed to load theme from \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return themes
    }

    /// Loads a single theme from a JSON file.
    public static func loadTheme(from url: URL) throws -> AppTheme {
        let data = try Data(contentsOf: url)
        let json = try JSONDecoder().decode(ThemeJSON.self, from: data)
        return try json.toAppTheme()
    }

    /// Opens the themes directory in Finder.
    public static func openThemesDirectory() {
        ensureThemesDirectoryExists()
        NSWorkspace.shared.open(themesDirectory)
    }

    /// Writes an example theme file to help users get started.
    public static func writeExampleTheme() {
        ensureThemesDirectoryExists()

        let exampleURL = themesDirectory.appendingPathComponent("example-theme.json")

        // Don't overwrite if it exists
        guard !FileManager.default.fileExists(atPath: exampleURL.path) else { return }

        let example = ThemeJSON(
            id: "example",
            displayName: "Example Theme (Edit Me!)",
            light: PaletteJSON(
                base: "#ffffff",
                text: "#1a1a2e",
                subtext0: "#6c6c8a",
                surface0: "#f0f0f5",
                surface1: "#d0d0dd",
                mauve: "#8b5cf6",
                blue: "#3b82f6",
                green: "#22c55e",
                teal: "#14b8a6",
                lavender: "#a78bfa",
                red: "#ef4444",
                yellow: "#eab308"
            ),
            dark: PaletteJSON(
                base: "#1a1a2e",
                text: "#eaeaff",
                subtext0: "#9999bb",
                surface0: "#2a2a42",
                surface1: "#3a3a55",
                mauve: "#a78bfa",
                blue: "#60a5fa",
                green: "#4ade80",
                teal: "#2dd4bf",
                lavender: "#c4b5fd",
                red: "#f87171",
                yellow: "#facc15"
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(example) {
            try? data.write(to: exampleURL)
        }
    }
}

// MARK: - JSON Schema

/// JSON structure for theme files.
struct ThemeJSON: Codable {
    let id: String
    let displayName: String
    let light: PaletteJSON
    let dark: PaletteJSON

    func toAppTheme() throws -> AppTheme {
        return AppTheme(
            id: id,
            displayName: displayName,
            lightPalette: try light.toThemePalette(),
            darkPalette: try dark.toThemePalette(),
            isSystemTheme: false
        )
    }
}

/// JSON structure for a single palette.
struct PaletteJSON: Codable {
    let base: String
    let text: String
    let subtext0: String
    let surface0: String
    let surface1: String
    let mauve: String
    let blue: String
    let green: String
    let teal: String
    let lavender: String
    let red: String
    let yellow: String

    func toThemePalette() throws -> ThemePalette {
        // Validate all colors are valid hex
        let colors = [base, text, subtext0, surface0, surface1, mauve, blue, green, teal, lavender, red, yellow]
        for color in colors {
            guard color.isValidHexColor else {
                throw ThemeLoadError.invalidHexColor(color)
            }
        }

        return ThemePalette(
            base: Color(hex: base),
            text: Color(hex: text),
            subtext0: Color(hex: subtext0),
            surface0: Color(hex: surface0),
            surface1: Color(hex: surface1),
            mauve: Color(hex: mauve),
            blue: Color(hex: blue),
            green: Color(hex: green),
            teal: Color(hex: teal),
            lavender: Color(hex: lavender),
            red: Color(hex: red),
            yellow: Color(hex: yellow)
        )
    }
}

/// Errors that can occur when loading themes.
public enum ThemeLoadError: LocalizedError {
    case invalidHexColor(String)
    case missingField(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHexColor(let color):
            return "Invalid hex color: \(color)"
        case .missingField(let field):
            return "Missing required field: \(field)"
        }
    }
}

// MARK: - Hex Validation

extension String {
    /// Checks if string is a valid hex color (#RGB, #RRGGBB, or without #)
    var isValidHexColor: Bool {
        let hex = self.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 3 || hex.count == 6 else { return false }
        return hex.allSatisfy { $0.isHexDigit }
    }
}
