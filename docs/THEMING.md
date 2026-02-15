# VoidReader Theming Guide

So you want to create a theme for VoidReader? Excellent. Just drop a JSON file in the themes folder and you're done. No coding, no compiling, no PRs.

This guide walks you through everything - from the quick start to the full color system.

## Quick Start

1. **Open the themes folder:** View menu → "Open Themes Folder..."
2. **Find the example:** VoidReader creates `example-theme.json` for you
3. **Copy and edit:** Duplicate it, rename it, change the colors
4. **Reload:** View menu → "Reload Themes" (or restart the app)
5. **Select:** Settings → Appearance → pick your theme

That's it. Your theme appears in the picker alongside System and Catppuccin.

## Philosophy

VoidReader themes follow a few guiding principles:

1. **Light AND Dark Required** - Every theme must provide both a light and dark variant. No single-mode themes. Users expect their apps to respect system appearance, and we honor that.

2. **System Theme is Special** - The default "System" theme uses native macOS semantic colors (`NSColor.textColor`, `NSColor.linkColor`, etc.). It's designed to blend seamlessly into macOS. Custom themes like Catppuccin override these with explicit colors.

3. **Syntax Colors, Not Chrome** - Themes control text/syntax colors, not window chrome, toolbar styling, or layout. VoidReader uses native macOS controls that inherit system appearance.

4. **Semantic Color Slots** - You define colors by purpose (headings, links, code), not by location. The app maps these semantically across all surfaces.

## What You're Writing

Think of a VoidReader theme as a color palette with 12 slots. You provide two palettes - one for light mode, one for dark mode. That's it. No CSS, no layout rules, just colors.

```
┌─────────────────────────────────────────────────────────┐
│  AppTheme                                               │
│  ├── id: "my-theme"                                     │
│  ├── displayName: "My Awesome Theme"                    │
│  ├── lightPalette: ThemePalette (12 colors)            │
│  └── darkPalette: ThemePalette (12 colors)             │
└─────────────────────────────────────────────────────────┘
```

## The Color Slots

Each `ThemePalette` has exactly 12 color slots:

### Base Colors (3)

| Slot | Purpose | Used For |
|------|---------|----------|
| `base` | Primary background | Reader view background (non-System themes) |
| `text` | Primary text | Body text, paragraphs |
| `subtext0` | Muted text | Secondary labels, markers, emphasis delimiters |

### Surface Colors (2)

| Slot | Purpose | Used For |
|------|---------|----------|
| `surface0` | Elevated surface | Code block backgrounds, cards |
| `surface1` | Borders/dividers | Table borders, separators |

### Accent Colors (7)

These are your syntax highlighting colors:

| Slot | Purpose | Editor Syntax | Reader View |
|------|---------|---------------|-------------|
| `mauve` | Headings | `# Heading` markers + text | - |
| `blue` | Links | `[text](url)` | Link text |
| `green` | Code | `` `inline` `` and ``` blocks | - |
| `teal` | Lists | `- ` and `1. ` markers | - |
| `lavender` | Quotes | `> ` markers | - |
| `red` | Errors | (reserved for future) | - |
| `yellow` | Warnings | (reserved for future) | - |

## Where Colors Apply

Your theme colors flow to these surfaces:

### 1. Editor (Edit Mode)
The syntax-highlighted markdown source. Uses AST-based highlighting:
- Headings → `mauve`
- Links → `blue`
- Code spans/blocks → `green`
- List markers → `teal`
- Blockquote markers → `lavender`
- Emphasis markers (`**`, `*`, `~~`) → `subtext0`
- Body text → `text`

### 2. Reader View (Read Mode)
The rendered markdown. For non-System themes:
- Body text → `text`
- Secondary text (list markers, HR) → `subtext0`
- Links → `blue`
- Code backgrounds → `surface0` (with opacity)

### 3. Mermaid Diagrams
Diagrams get `themeVariables` generated from your palette:
- Node backgrounds → `surface0`
- Node text → `text`
- Lines/arrows → `subtext0`
- Borders → `surface1`

### 4. Code Blocks
Currently uses Highlightr's built-in themes (atom-one-dark/light). Full theme integration is a future enhancement.

## Creating a Theme

### Step 1: Open the Themes Folder

Go to **View → Open Themes Folder...**

This opens:
```
~/Library/Application Support/VoidReader/themes/
```

VoidReader automatically creates an `example-theme.json` to get you started.

### Step 2: Create Your Theme File

Copy the example or create a new `.json` file:

```json
{
  "id": "my-theme",
  "displayName": "My Awesome Theme",
  "light": {
    "base": "#ffffff",
    "text": "#24292e",
    "subtext0": "#6a737d",
    "surface0": "#f6f8fa",
    "surface1": "#e1e4e8",
    "mauve": "#6f42c1",
    "blue": "#0366d6",
    "green": "#22863a",
    "teal": "#0598bc",
    "lavender": "#6f42c1",
    "red": "#d73a49",
    "yellow": "#dbab09"
  },
  "dark": {
    "base": "#0d1117",
    "text": "#c9d1d9",
    "subtext0": "#8b949e",
    "surface0": "#161b22",
    "surface1": "#30363d",
    "mauve": "#d2a8ff",
    "blue": "#58a6ff",
    "green": "#7ee787",
    "teal": "#39c5cf",
    "lavender": "#d2a8ff",
    "red": "#f85149",
    "yellow": "#d29922"
  }
}
```

**Requirements:**
- `id` must be unique (lowercase, no spaces recommended)
- `displayName` is what appears in the Settings picker
- Both `light` and `dark` palettes are required
- All 12 color slots must be present in each palette
- Colors must be valid hex (`#RGB` or `#RRGGBB`)

### Step 3: Reload Themes

Either:
- **View → Reload Themes** (Cmd+Shift+Option+T)
- Or restart VoidReader

### Step 4: Select Your Theme

**Settings → Appearance** and pick your theme from the dropdown.

That's it! No compiling, no code, no PRs.

## Invariants (What You Cannot Change)

These are fixed by design:

| Aspect | Why |
|--------|-----|
| **Typography** | Font family, sizes, heading scales are user preferences, not theme concerns |
| **Layout** | Margins, padding, spacing are fixed for consistent reading experience |
| **Color slot names** | The 12 slots are semantic - can't add or rename them |
| **Light + Dark requirement** | Every theme must have both variants |
| **Window chrome** | Title bar, toolbar use native macOS styling |
| **System theme behavior** | The System theme always uses macOS semantic colors |

## Design Tips

### Contrast Matters
- Ensure sufficient contrast between `text` and `base`
- `subtext0` should be readable but clearly muted
- Test both light and dark modes!

### Syntax Highlighting Harmony
- Pick accent colors that work together
- `mauve`, `blue`, `green`, `teal`, `lavender` will appear near each other in complex documents
- Consider colorblind users - don't rely solely on red/green distinction

### Steal From the Best
Look at established color schemes for inspiration:
- [Catppuccin](https://github.com/catppuccin/catppuccin) - What we ship
- [Dracula](https://draculatheme.com/)
- [Nord](https://www.nordtheme.com/)
- [Solarized](https://ethanschoonover.com/solarized/)
- [GitHub's Primer](https://primer.style/primitives/colors)

### Test With Real Content
Don't just test with "Hello World". Open a complex markdown file with:
- Multiple heading levels
- Nested lists
- Code blocks with different languages
- Mermaid diagrams
- Tables
- Blockquotes
- Inline code mixed with links

## Future Enhancements

Some things we'd like to add:

- **Full code block theming** - Custom Highlightr CSS from theme palette
- **Theme preview** - Live preview swatches in Settings
- **File watcher** - Auto-reload when theme files change
- **Theme validation UI** - Show errors for malformed themes in Settings

## Troubleshooting

### Theme doesn't appear in Settings
- Check the file is in `~/Library/Application Support/VoidReader/themes/`
- Ensure the file extension is `.json`
- Use **View → Reload Themes** or restart the app
- Check Console.app for error messages (search "VoidReader")

### "Invalid hex color" error
- Colors must be `#RGB` or `#RRGGBB` format
- The `#` is optional but recommended
- No alpha channel support (no `#RRGGBBAA`)

### Theme loads but colors look wrong
- Verify you're testing in the right appearance mode (light/dark)
- Check that the color is in the correct palette (`light` vs `dark`)
- Remember: some colors only affect editor mode, not reader mode

### JSON syntax errors
- Use a JSON validator (many free online)
- Common issues: trailing commas, missing quotes, unescaped characters
- The example theme is valid - diff against it to find issues

## Reference

### Theme File Location
```
~/Library/Application Support/VoidReader/themes/
```

### Built-in Theme Source
See `Sources/VoidReaderCore/Theming/CatppuccinTheme.swift` for the Catppuccin implementation. It's a well-documented color scheme with official hex values.

### Menu Commands
- **View → Open Themes Folder...** - Opens themes directory in Finder
- **View → Reload Themes** (Cmd+Shift+Option+T) - Reloads all user themes

---

Questions? Issues? Open a GitHub issue.
