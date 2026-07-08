import SwiftUI

/// Registry of available themes.
/// Combines built-in themes with user-created themes from the themes directory.
public final class ThemeRegistry: @unchecked Sendable {
    public static let shared = ThemeRegistry()

    /// Built-in themes that ship with the app
    public let builtInThemes: [AppTheme] = [
        .system,
        .catppuccin
    ]

    /// Serializes access to `_userThemes` — reloadUserThemes() can run off the
    /// main thread while `themes`/`userThemes` are read, and the class is
    /// `@unchecked Sendable`, so the mutable state needs a lock to make that safe.
    private let lock = NSLock()
    private var _userThemes: [AppTheme] = []

    /// User themes loaded from ~/Library/Application Support/VoidReader/themes/
    public var userThemes: [AppTheme] {
        lock.lock(); defer { lock.unlock() }
        return _userThemes
    }

    /// All available themes. Built-in themes first, then user themes.
    public var themes: [AppTheme] {
        lock.lock(); let user = _userThemes; lock.unlock()
        return builtInThemes + user
    }

    /// The default theme (always System)
    public var defaultTheme: AppTheme { .system }

    /// Find theme by ID
    public func theme(id: String) -> AppTheme? {
        themes.first { $0.id == id }
    }

    /// Get theme by ID, falling back to default if not found
    public func themeOrDefault(id: String) -> AppTheme {
        theme(id: id) ?? defaultTheme
    }

    /// Reload user themes from disk
    public func reloadUserThemes() {
        // Load outside the lock (disk I/O), then swap in under it.
        let loaded = ThemeLoader.loadUserThemes()
        lock.lock(); _userThemes = loaded; lock.unlock()
    }

    /// Opens the themes directory in Finder and creates example if needed
    public func openThemesDirectory() {
        ThemeLoader.writeExampleTheme()
        ThemeLoader.openThemesDirectory()
    }

    private init() {
        // Load user themes synchronously - should be fast for typical use
        reloadUserThemes()
    }
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
