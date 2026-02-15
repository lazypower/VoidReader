# Theming

This capability defines VoidReader's theming system including light/dark mode support, color tokens, syntax highlighting, and theme selection.

## ADDED Requirements

### Requirement: Theme Selection
The application SHALL provide a theme picker in Settings allowing users to choose from available themes.

#### Scenario: Theme picker UI
- **WHEN** user opens Settings
- **THEN** an "Appearance" section shows available themes
- **AND** each theme displays a preview swatch of its accent colors

#### Scenario: Theme selection persistence
- **WHEN** user selects a different theme
- **THEN** the selection is applied immediately
- **AND** the selection persists across app restarts

#### Scenario: Default theme
- **WHEN** the app is first launched
- **THEN** "System" theme is selected by default
- **AND** the app uses native macOS semantic colors

#### Scenario: Shipped themes
- **WHEN** user views the theme picker
- **THEN** "System" and "Catppuccin" are available
- **AND** additional user-created themes appear if discovered

### Requirement: Theme Structure
Every theme SHALL define both light and dark variants. Single-mode themes are not permitted.

#### Scenario: Theme variant requirement
- **WHEN** a theme is loaded
- **THEN** it MUST provide both a light palette and a dark palette
- **AND** themes missing either variant are invalid

#### Scenario: System theme variants
- **WHEN** "System" theme is active
- **THEN** light variant uses NSColor semantic colors (textColor, linkColor, etc.)
- **AND** dark variant uses NSColor semantic colors (automatically adapted)

#### Scenario: Catppuccin theme variants
- **WHEN** "Catppuccin" theme is active
- **THEN** light variant uses Latte palette
- **AND** dark variant uses Mocha palette

### Requirement: System Appearance Detection
The application SHALL automatically detect and follow macOS system appearance (light/dark mode).

#### Scenario: System in light mode
- **WHEN** macOS is set to Light appearance
- **THEN** the application uses the light theme (Catppuccin Latte)
- **AND** all UI elements reflect light theme colors

#### Scenario: System in dark mode
- **WHEN** macOS is set to Dark appearance
- **THEN** the application uses the dark theme (Catppuccin Mocha)
- **AND** all UI elements reflect dark theme colors

#### Scenario: System appearance changes
- **WHEN** the user toggles system appearance while the app is running
- **THEN** the application immediately switches themes
- **AND** no restart is required

### Requirement: Catppuccin Editor Theme
The application SHALL use Catppuccin color palettes for editor syntax highlighting only: Latte for light mode, Mocha for dark mode.

#### Scenario: Catppuccin Mocha syntax colors (dark)
- **WHEN** system is in dark mode and editor is active
- **THEN** syntax highlighting uses Catppuccin Mocha palette
- **AND** colors include Mauve `#cba6f7`, Blue `#89b4fa`, Green `#a6e3a1`, Teal `#94e2d5`

#### Scenario: Catppuccin Latte syntax colors (light)
- **WHEN** system is in light mode and editor is active
- **THEN** syntax highlighting uses Catppuccin Latte palette
- **AND** colors include Mauve `#8839ef`, Blue `#1e66f5`, Green `#40a02b`, Teal `#179299`

### Requirement: Editor Syntax Token System
The application SHALL use semantic syntax tokens for editor highlighting that map to Catppuccin palette values.

#### Scenario: Token usage in editor
- **WHEN** the editor highlights markdown syntax
- **THEN** it uses semantic tokens (e.g., `SyntaxTheme.heading`, `SyntaxTheme.link`)
- **AND** tokens resolve to appropriate Catppuccin colors based on system appearance

#### Scenario: Token categories
- **WHEN** the syntax theme is initialized
- **THEN** it provides tokens for: heading, emphasis, link, code, listMarker, blockquote, horizontalRule

### Requirement: Reader View Native Colors
The application SHALL use native macOS semantic colors for reader view, ensuring the reading experience feels native and adapts automatically to system appearance.

#### Scenario: Text rendering
- **WHEN** markdown is rendered in reader view
- **THEN** body text uses `NSColor.textColor`
- **AND** headings use `NSColor.labelColor` with appropriate weight
- **AND** links use `NSColor.linkColor`

#### Scenario: Code block rendering
- **WHEN** a code block is rendered
- **THEN** background uses `NSColor.textBackgroundColor` or subtle system gray
- **AND** text uses `NSColor.textColor`
- **AND** the block adapts naturally to light/dark mode

#### Scenario: Table rendering
- **WHEN** a table is rendered
- **THEN** borders use `NSColor.separatorColor`
- **AND** header row has subtle system background distinction
- **AND** styling follows macOS HIG patterns

### Requirement: Editor Syntax Highlighting
The application SHALL apply Catppuccin-based syntax highlighting to markdown source in edit mode.

#### Scenario: Heading syntax
- **WHEN** a line begins with `#` markers
- **THEN** the markers and heading text are colored Mauve (`#cba6f7` dark / `#8839ef` light)

#### Scenario: Emphasis syntax
- **WHEN** text contains `*`, `**`, `_`, or `__` markers
- **THEN** the markers are colored Subtext0 (muted)
- **AND** the emphasized text retains appropriate styling

#### Scenario: Link syntax
- **WHEN** text contains `[text](url)` pattern
- **THEN** brackets and URL are colored Blue (`#89b4fa` dark / `#1e66f5` light)
- **AND** link text is distinguishable

#### Scenario: Code syntax
- **WHEN** text contains backticks or fenced code blocks
- **THEN** backticks/fences are colored Green (`#a6e3a1` dark / `#40a02b` light)
- **AND** code content has distinct background

#### Scenario: List syntax
- **WHEN** lines begin with `-`, `*`, `+`, or numbers
- **THEN** markers are colored Teal (`#94e2d5` dark / `#179299` light)

#### Scenario: Blockquote syntax
- **WHEN** lines begin with `>`
- **THEN** the `>` marker is colored Lavender (`#b4befe` dark / `#7287fd` light)

### Requirement: Mermaid Diagram Theming
The application SHALL pass theme configuration to mermaid.js to ensure diagrams match the application theme.

#### Scenario: Dark mode diagram
- **WHEN** a mermaid diagram renders in dark mode
- **THEN** the diagram uses dark theme colors
- **AND** nodes and edges are visible against dark background

#### Scenario: Light mode diagram
- **WHEN** a mermaid diagram renders in light mode
- **THEN** the diagram uses light theme colors
- **AND** nodes and edges are visible against light background

#### Scenario: Theme change with visible diagram
- **WHEN** system appearance changes while a diagram is visible
- **THEN** the diagram re-renders with updated theme

### Requirement: Accessibility Contrast
The application SHALL maintain WCAG AA contrast ratios (4.5:1 for text, 3:1 for UI) in both themes.

#### Scenario: Text contrast
- **WHEN** text is rendered on any background
- **THEN** the contrast ratio meets WCAG AA (4.5:1 minimum)

#### Scenario: Interactive element contrast
- **WHEN** buttons, links, or controls are rendered
- **THEN** the contrast ratio meets WCAG AA (3:1 minimum)

### Requirement: Font Configuration
The application SHALL allow users to configure fonts for reader and editor views via preferences.

#### Scenario: Reader font family
- **WHEN** user selects a font family for reader view
- **THEN** rendered markdown body text uses that font
- **AND** the setting persists across sessions

#### Scenario: Reader font size
- **WHEN** user adjusts reader font size
- **THEN** body text scales accordingly
- **AND** heading sizes scale proportionally

#### Scenario: Editor font family
- **WHEN** user selects a font family for editor view
- **THEN** source text uses that font (should be monospace)
- **AND** syntax highlighting colors apply to the chosen font

#### Scenario: Editor font size
- **WHEN** user adjusts editor font size
- **THEN** source text scales accordingly
- **AND** gutter/line numbers scale proportionally

#### Scenario: Code block font
- **WHEN** a code block is rendered in reader view
- **THEN** it uses the configured monospace font
- **AND** defaults to SF Mono or system monospace

#### Scenario: Line height adjustment
- **WHEN** user adjusts line height/spacing
- **THEN** both reader and editor views reflect the change
- **AND** readability improves for user's preference

#### Scenario: Quick font size shortcuts
- **WHEN** user presses Cmd++ or Cmd+-
- **THEN** font size increases or decreases
- **AND** Cmd+0 resets to default size

### Requirement: Appearance Override (User Choice)
The application SHALL provide an optional in-app setting to override system appearance. This is an explicit user choice to deviate from system defaults.

#### Scenario: Default follows system
- **WHEN** appearance override is set to "System" (default)
- **THEN** app follows macOS system appearance
- **AND** theme's light/dark variant switches automatically

#### Scenario: Override to always dark
- **WHEN** user explicitly sets appearance to "Always Dark"
- **THEN** app uses theme's dark variant regardless of system setting
- **AND** user accepts responsibility for potential visual clash

#### Scenario: Override to always light
- **WHEN** user explicitly sets appearance to "Always Light"
- **THEN** app uses theme's light variant regardless of system setting
- **AND** user accepts responsibility for potential visual clash
