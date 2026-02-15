import SwiftUI

/// A complete theme with both light and dark variants.
/// Every theme MUST define both palettes - single-mode themes are not permitted.
public struct AppTheme: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let lightPalette: ThemePalette
    public let darkPalette: ThemePalette

    /// Whether this theme uses native macOS semantic colors
    public let isSystemTheme: Bool

    public init(
        id: String,
        displayName: String,
        lightPalette: ThemePalette,
        darkPalette: ThemePalette,
        isSystemTheme: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.lightPalette = lightPalette
        self.darkPalette = darkPalette
        self.isSystemTheme = isSystemTheme
    }

    /// Returns the appropriate palette for the given color scheme
    public func palette(for colorScheme: ColorScheme) -> ThemePalette {
        switch colorScheme {
        case .light:
            return lightPalette
        case .dark:
            return darkPalette
        @unknown default:
            return darkPalette
        }
    }

    /// Returns mermaid.js themeVariables config for the given color scheme
    public func mermaidThemeVariables(for colorScheme: ColorScheme) -> [String: String] {
        // For system theme, use mermaid's built-in themes
        if isSystemTheme {
            return [:] // Empty = use default/dark built-in
        }

        let p = palette(for: colorScheme)
        return [
            "primaryColor": p.surface0.hexString,
            "primaryTextColor": p.text.hexString,
            "primaryBorderColor": p.surface1.hexString,
            "lineColor": p.subtext0.hexString,
            "secondaryColor": p.surface1.hexString,
            "tertiaryColor": p.surface0.hexString,
            "background": p.base.hexString,
            "mainBkg": p.surface0.hexString,
            "nodeBorder": p.mauve.hexString,
            "clusterBkg": p.surface0.hexString,
            "clusterBorder": p.surface1.hexString,
            "titleColor": p.text.hexString,
            "edgeLabelBackground": p.surface0.hexString,
            "textColor": p.text.hexString,
            "nodeTextColor": p.text.hexString
        ]
    }

    /// Returns the mermaid theme name to use
    public func mermaidThemeName(for colorScheme: ColorScheme) -> String {
        if isSystemTheme {
            return colorScheme == .dark ? "dark" : "default"
        }
        return "base" // Use 'base' for custom themeVariables
    }
}

// MARK: - Built-in Themes

extension AppTheme {
    /// System theme - uses native macOS semantic colors (default)
    public static let system = AppTheme(
        id: "system",
        displayName: "System",
        lightPalette: .systemLight,
        darkPalette: .systemDark,
        isSystemTheme: true
    )

    /// Catppuccin theme - Latte (light) / Mocha (dark)
    public static let catppuccin = AppTheme(
        id: "catppuccin",
        displayName: "Catppuccin",
        lightPalette: .catppuccinLatte,
        darkPalette: .catppuccinMocha,
        isSystemTheme: false
    )
}
