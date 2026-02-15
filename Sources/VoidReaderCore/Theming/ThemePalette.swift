import SwiftUI
import AppKit

/// Color palette for a theme variant (light or dark).
/// Every theme must define both a light and dark palette.
public struct ThemePalette: Equatable, Sendable {
    // MARK: - Base Colors
    public let base: Color        // Primary background
    public let text: Color        // Primary text
    public let subtext0: Color    // Muted/secondary text

    // MARK: - Surface Colors
    public let surface0: Color    // Elevated surface (code blocks, cards)
    public let surface1: Color    // Borders, dividers

    // MARK: - Accent Colors (for syntax highlighting)
    public let mauve: Color       // Headings
    public let blue: Color        // Links
    public let green: Color       // Code/backticks
    public let teal: Color        // List markers
    public let lavender: Color    // Blockquotes
    public let red: Color         // Errors, deletions
    public let yellow: Color      // Warnings, highlights

    public init(
        base: Color,
        text: Color,
        subtext0: Color,
        surface0: Color,
        surface1: Color,
        mauve: Color,
        blue: Color,
        green: Color,
        teal: Color,
        lavender: Color,
        red: Color,
        yellow: Color
    ) {
        self.base = base
        self.text = text
        self.subtext0 = subtext0
        self.surface0 = surface0
        self.surface1 = surface1
        self.mauve = mauve
        self.blue = blue
        self.green = green
        self.teal = teal
        self.lavender = lavender
        self.red = red
        self.yellow = yellow
    }
}

// MARK: - Hex Color Initializer

extension Color {
    /// Initialize Color from hex string (e.g., "#cba6f7" or "cba6f7")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: Double
        switch hex.count {
        case 6: // RGB
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        case 8: // ARGB
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 0
            g = 0
            b = 0
        }

        self.init(red: r, green: g, blue: b)
    }

    /// Returns hex string representation
    var hexString: String {
        guard let components = NSColor(self).usingColorSpace(.deviceRGB) else {
            return "#000000"
        }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - System Theme Palette (Native macOS Colors)

extension ThemePalette {
    /// System light palette using macOS semantic colors
    /// Note: Accent colors are adjusted for better readability on light backgrounds
    public static let systemLight = ThemePalette(
        base: Color(nsColor: .textBackgroundColor),
        text: Color(nsColor: .textColor),
        subtext0: Color(nsColor: .secondaryLabelColor),
        surface0: Color(nsColor: .controlBackgroundColor),
        surface1: Color(nsColor: .separatorColor),
        mauve: Color(hex: "#8839ef"),     // Darker purple for headings
        blue: Color(nsColor: .linkColor),
        green: Color(hex: "#1e7d34"),     // Dark green for code (readable on white)
        teal: Color(hex: "#0d7377"),      // Dark teal for list markers
        lavender: Color(hex: "#6c5ce7"),  // Dark lavender for blockquotes
        red: Color(nsColor: .systemRed),
        yellow: Color(hex: "#b58900")     // Dark gold for warnings
    )

    /// System dark palette using macOS semantic colors
    /// (Same colors - they adapt automatically)
    public static let systemDark = ThemePalette(
        base: Color(nsColor: .textBackgroundColor),
        text: Color(nsColor: .textColor),
        subtext0: Color(nsColor: .secondaryLabelColor),
        surface0: Color(nsColor: .controlBackgroundColor),
        surface1: Color(nsColor: .separatorColor),
        mauve: Color(nsColor: .systemPurple),
        blue: Color(nsColor: .linkColor),
        green: Color(nsColor: .systemGreen),
        teal: Color(nsColor: .systemTeal),
        lavender: Color(nsColor: .systemIndigo),
        red: Color(nsColor: .systemRed),
        yellow: Color(nsColor: .systemYellow)
    )
}
