# Design: Theming Support

## Context
VoidReader needs a cohesive theming system that works across native SwiftUI views, AttributedString rendering, and WKWebView (mermaid). The user prioritizes accessibility and has expressed preference for Catppuccin Mocha.

## Goals
- Seamless light/dark mode switching following system preferences
- Reader view uses native macOS semantic colors (feels native)
- Editor syntax highlighting uses Catppuccin Latte (light) ↔ Mocha (dark)
- Native syntax highlighting without JavaScript dependencies
- Mermaid diagrams adapt to system appearance

## Non-Goals
- Custom theme editor / user-defined themes (v1)
- Additional theme palettes beyond Catppuccin (v1)
- Per-document theme settings

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
Pass theme via mermaid.initialize() config, using Catppuccin-compatible values.

```javascript
mermaid.initialize({
    theme: 'base',
    themeVariables: {
        primaryColor: theme.surface,
        primaryTextColor: theme.text,
        primaryBorderColor: theme.accent,
        lineColor: theme.textMuted,
        // ... etc
    }
});
```

**Re-rendering on theme change:** Listen for appearance change notification and call mermaid.render() again with updated config.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Catppuccin colors may not suit all users | System override allows forcing light/dark |
| Syntax highlighting regex may miss edge cases | Start with common patterns, iterate |
| Mermaid theme may not perfectly match | Use 'base' theme with explicit variables |

## Open Questions
- Should we expose a "high contrast" variant for accessibility?
- Should syntax highlighting be configurable (on/off) in preferences?
