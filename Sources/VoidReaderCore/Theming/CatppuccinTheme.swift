import SwiftUI

// MARK: - Catppuccin Palettes
// Official Catppuccin color definitions: https://github.com/catppuccin/catppuccin

extension ThemePalette {
    /// Catppuccin Latte (light variant)
    public static let catppuccinLatte = ThemePalette(
        base: Color(hex: "#eff1f5"),
        text: Color(hex: "#4c4f69"),
        subtext0: Color(hex: "#6c6f85"),
        surface0: Color(hex: "#ccd0da"),
        surface1: Color(hex: "#bcc0cc"),
        mauve: Color(hex: "#8839ef"),
        blue: Color(hex: "#1e66f5"),
        green: Color(hex: "#40a02b"),
        teal: Color(hex: "#179299"),
        lavender: Color(hex: "#7287fd"),
        red: Color(hex: "#d20f39"),
        yellow: Color(hex: "#df8e1d")
    )

    /// Catppuccin Mocha (dark variant)
    public static let catppuccinMocha = ThemePalette(
        base: Color(hex: "#1e1e2e"),
        text: Color(hex: "#cdd6f4"),
        subtext0: Color(hex: "#a6adc8"),
        surface0: Color(hex: "#313244"),
        surface1: Color(hex: "#45475a"),
        mauve: Color(hex: "#cba6f7"),
        blue: Color(hex: "#89b4fa"),
        green: Color(hex: "#a6e3a1"),
        teal: Color(hex: "#94e2d5"),
        lavender: Color(hex: "#b4befe"),
        red: Color(hex: "#f38ba8"),
        yellow: Color(hex: "#f9e2af")
    )
}
