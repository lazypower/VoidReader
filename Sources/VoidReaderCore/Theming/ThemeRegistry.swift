import SwiftUI

/// Registry of available themes.
/// Provides access to built-in themes and (future) user-created themes.
public final class ThemeRegistry: @unchecked Sendable {
    public static let shared = ThemeRegistry()

    /// All available themes. System theme is always first (default).
    public let themes: [AppTheme] = [
        .system,
        .catppuccin
    ]

    /// The default theme
    public var defaultTheme: AppTheme { themes[0] }

    /// Find theme by ID
    public func theme(id: String) -> AppTheme? {
        themes.first { $0.id == id }
    }

    /// Get theme by ID, falling back to default if not found
    public func themeOrDefault(id: String) -> AppTheme {
        theme(id: id) ?? defaultTheme
    }

    private init() {}
}

// MARK: - Current Theme Access

/// Environment key for the current theme
private struct CurrentThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .system
}

extension EnvironmentValues {
    /// The currently selected theme
    public var currentTheme: AppTheme {
        get { self[CurrentThemeKey.self] }
        set { self[CurrentThemeKey.self] = newValue }
    }
}

extension View {
    /// Sets the theme for this view and its descendants
    public func theme(_ theme: AppTheme) -> some View {
        environment(\.currentTheme, theme)
    }
}
