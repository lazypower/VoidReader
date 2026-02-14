# Change: Add Theming Support

## Why
Accessibility and user comfort require proper light/dark mode support. Users shouldn't be flash-banged at night, and the app should respect system appearance preferences. A cohesive theme system ensures visual consistency across reader view, editor, and mermaid diagrams.

## What Changes
- Implement theme system with semantic color tokens
- Bundle Catppuccin Latte (light) and Mocha (dark) as default themes
- Auto-switch based on macOS system appearance
- Apply theming to: rendered markdown, source editor syntax highlighting, mermaid diagrams, and UI chrome
- Optional: app-level appearance override in preferences

## Impact
- Affected specs: theming (new)
- Affected code: All views, color definitions, mermaid configuration
