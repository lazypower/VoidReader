# Design: Theming Support

## Context
VoidReader needs a cohesive theming system that works across native SwiftUI views, AttributedString rendering, and WKWebView (mermaid). The user prioritizes accessibility and has expressed preference for Catppuccin Mocha. The system should support multiple themes with a picker UI, starting with Catppuccin and designed for future expansion.

## Goals
- Seamless light/dark mode switching following system preferences
- Theme picker in Settings with support for multiple themes
- Theme architecture that supports adding new themes easily
- **All surfaces adopt selected theme coherently:** reader, editor, mermaid, code blocks
- System theme = native macOS semantic colors (blends in)
- Custom themes (Catppuccin, etc.) = full palette applied everywhere

## Non-Goals
- Custom theme editor / user-defined themes (v1)
- Appearance override (follow system only)
- UI chrome theming (rely on macOS semantic colors)
- Per-document theme settings

## Architecture

### Key Principle: Default = Native macOS
The app blends into macOS by default. The "System" theme uses NSColor semantic colors, meaning it automatically adapts to system appearance without asserting a custom style. Themed alternatives (Catppuccin, user themes) are opt-in choices.

### Theme System Location
Theme definitions live in `VoidReaderCore/Theming/` (Swift Package) so they're available to both the app and QuickLook extension.

```
Sources/VoidReaderCore/Theming/
├── ThemePalette.swift       # Color palette struct
├── AppTheme.swift           # Theme with light/dark variants (BOTH required)
├── ThemeRegistry.swift      # Available themes registry
├── SystemTheme.swift        # Native macOS semantic colors
└── CatppuccinTheme.swift    # Catppuccin palette definitions
```

### Core Types

```swift
/// Color palette for a theme variant (light or dark)
public struct ThemePalette {
    public let base, text, subtext0: Color
    public let surface0, surface1: Color
    public let mauve, blue, green, teal, lavender, red, yellow: Color

    /// System theme uses NSColor semantic colors
    public static func system(for colorScheme: ColorScheme) -> ThemePalette
}

/// A complete theme - MUST define BOTH light AND dark variants
public struct AppTheme: Identifiable {
    public let id: String           // e.g., "system", "catppuccin"
    public let displayName: String  // e.g., "System", "Catppuccin"
    public let lightPalette: ThemePalette  // Required
    public let darkPalette: ThemePalette   // Required

    func palette(for colorScheme: ColorScheme) -> ThemePalette
    func mermaidThemeVariables(for colorScheme: ColorScheme) -> [String: String]
}

/// Registry of available themes
public final class ThemeRegistry {
    public static let shared = ThemeRegistry()
    public let themes: [AppTheme] = [.system, .catppuccin]  // System is first/default
    public func theme(id: String) -> AppTheme?
}
```

### Shipped Themes

**System (default)**
- Light: NSColor.textColor, NSColor.linkColor, NSColor.separatorColor, etc.
- Dark: Same NSColor values (automatically adapted by macOS)
- Mermaid: Uses built-in "default" / "dark" themes

**Catppuccin (alternative)**
- Light: Latte palette
- Dark: Mocha palette
- Mermaid: Custom themeVariables from palette

### Adding Future Themes
To add a new theme:
1. Create palette constants (e.g., `DraculaTheme.swift`)
2. Define BOTH lightPalette AND darkPalette
3. Add `AppTheme.dracula` static property
4. Add to `ThemeRegistry.themes` array

Future: User themes discovered from `~/Library/Application Support/VoidReader/Themes/`

### Editor Syntax Highlighting
SwiftUI's `TextEditor` only binds to `String`, not `AttributedString`. For syntax highlighting:

1. Create `SyntaxHighlightingEditor` as `NSViewRepresentable` wrapping `NSTextView`
2. **Reuse swift-markdown parser** - same parser used for preview rendering
3. Walk AST and use `SourceRange` on each node to get positions in source text
4. Apply theme colors based on node type (Heading, Emphasis, Link, CodeBlock, etc.)
5. For System theme: use NSColor semantic colors for syntax tokens
6. For Catppuccin: use palette accent colors (mauve, blue, green, etc.)
7. Debounce re-parsing for performance (already doing this for preview)

**Why AST over Regex:**
- swift-markdown already parses GFM (tables, task lists, strikethrough)
- AST understands context (no false positives on escaped chars, code blocks, etc.)
- Single source of truth - same parser for highlighting AND rendering
- No brittle regex maintenance

## Decisions

### Decision: Catppuccin Color Palette
Use the official Catppuccin palette definitions.

**Mocha (Dark) - Primary Colors:**
| Token | Name | Hex |
|-------|------|-----|
| base | Base | `#1e1e2e` |
| text | Text | `#cdd6f4` |
| subtext0 | Subtext0 | `#a6adc8` |
| surface0 | Surface0 | `#313244` |
| surface1 | Surface1 | `#45475a` |
| mauve | Mauve | `#cba6f7` |
| blue | Blue | `#89b4fa` |
| green | Green | `#a6e3a1` |
| teal | Teal | `#94e2d5` |
| lavender | Lavender | `#b4befe` |
| red | Red | `#f38ba8` |
| yellow | Yellow | `#f9e2af` |

**Latte (Light) - Primary Colors:**
| Token | Name | Hex |
|-------|------|-----|
| base | Base | `#eff1f5` |
| text | Text | `#4c4f69` |
| subtext0 | Subtext0 | `#6c6f85` |
| surface0 | Surface0 | `#ccd0da` |
| surface1 | Surface1 | `#bcc0cc` |
| mauve | Mauve | `#8839ef` |
| blue | Blue | `#1e66f5` |
| green | Green | `#40a02b` |
| teal | Teal | `#179299` |
| lavender | Lavender | `#7287fd` |
| red | Red | `#d20f39` |
| yellow | Yellow | `#df8e1d` |

### Decision: Reader View - Native macOS Colors
Reader view uses system semantic colors for a native feel:

| Element | macOS Color | Notes |
|---------|-------------|-------|
| Body text | `NSColor.textColor` | Adapts to appearance |
| Headings | `NSColor.labelColor` | With weight variation |
| Links | `NSColor.linkColor` | Standard blue |
| Code background | `NSColor.textBackgroundColor` | Subtle distinction |
| Borders | `NSColor.separatorColor` | Tables, hr |

### Decision: Editor Syntax - Catppuccin Tokens
Editor syntax highlighting uses Catppuccin palette:

| Syntax Token | Catppuccin Color | Usage |
|--------------|------------------|-------|
| `heading` | Mauve | `#` markers and text |
| `emphasis` | Subtext0 | `*/_` markers |
| `link` | Blue | `[]()` syntax |
| `code` | Green | Backticks, fences |
| `listMarker` | Teal | `-/*` and numbers |
| `blockquote` | Lavender | `>` markers |

### Decision: Native Syntax Highlighting
Implement markdown syntax highlighting in pure Swift using NSAttributedString/AttributedString, avoiding TextKit 2 or highlight.js dependency.

**Rationale:**
- Keeps editor fully native
- No WebView overhead for source editing
- Full control over colors
- Simpler architecture

**Syntax patterns to highlight:**
```swift
enum MarkdownSyntax {
    case heading      // ^#{1,6}\s
    case bold         // \*\*...\*\* or __...__
    case italic       // \*...\* or _..._
    case code         // `...` or ```...```
    case link         // \[...\]\(...\)
    case image        // !\[...\]\(...\)
    case listMarker   // ^[\-\*\+]|\d+\.
    case blockquote   // ^>
    case horizontalRule // ^(\-{3,}|\*{3,}|_{3,})$
}
```

### Decision: Mermaid Theme Injection
Pass theme via mermaid.initialize() config, using selected theme's palette values.

```javascript
mermaid.initialize({
    theme: 'base',
    themeVariables: {
        primaryColor: palette.surface0,
        primaryTextColor: palette.text,
        primaryBorderColor: palette.surface1,
        lineColor: palette.subtext0,
        secondaryColor: palette.surface1,
        background: palette.base,
        // ... etc
    }
});
```

Update `mermaid-template.html` to use `{{MERMAID_THEME_VARIABLES}}` placeholder.
Update `MermaidWebView.swift` to generate JSON from `theme.mermaidThemeVariables(for: colorScheme)`.

**Re-rendering on theme change:** Already handled - `updateNSView` detects `colorScheme` changes and reloads.

### Decision: Theme Picker UI
Add "Appearance" section to SettingsView:

```swift
Section("Appearance") {
    Picker("Theme", selection: $selectedThemeID) {
        ForEach(ThemeRegistry.shared.themes) { theme in
            HStack {
                ThemePreviewSwatch(theme: theme)
                Text(theme.displayName)
            }
            .tag(theme.id)
        }
    }
}
```

Store selection via `@AppStorage("selectedThemeID")`.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| User may not like Catppuccin | Theme picker allows adding alternatives |
| Syntax highlighting regex may miss edge cases | Start with common patterns, iterate |
| Mermaid theme may not perfectly match | Use 'base' theme with explicit variables |
| NSTextView complexity | Well-documented pattern in macOS development |

## Resolved Questions
- ~~Should we expose a "high contrast" variant?~~ Not for v1, use theme picker instead
- ~~Should syntax highlighting be configurable?~~ Not for v1, always on in edit mode
