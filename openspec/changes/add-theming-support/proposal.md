# Change: Add Theming Support

## Why
VoidReader should blend naturally into macOS, respecting system appearance and using native semantic colors by default. For users who want a more stylized experience, themed alternatives provide a cohesive, intentional look across all app surfaces. A well-designed theme system enables future extensibility where users can create and curate their own themes.

## What Changes
- Implement theme system where **every theme requires both light AND dark variants**
- "System" theme (default) uses native macOS semantic colors - blends into macOS naturally
- "Catppuccin" theme ships as an alternative (Latte for light, Mocha for dark)
- Add theme picker in Settings for choosing between available themes
- Auto-switch theme variants based on macOS system appearance (always follows system by default)
- Optional appearance override for users who explicitly want to deviate
- Apply selected theme coherently across ALL surfaces: reader, editor, mermaid diagrams
- Design architecture for future user-created theme discovery

## Key Principles
- **Default = Native:** System theme uses NSColor semantic colors, no style clash
- **Themes = Opt-in:** User explicitly chooses Catppuccin or other themes
- **Always Light+Dark:** No single-mode themes; every theme adapts to system appearance
- **User Control:** Appearance override is available but requires explicit user action
- **Consistency:** When themed, ALL surfaces reflect the theme coherently

## Scope Adjustments
- **Skipped:** UI chrome theming (macOS semantic colors handle this natively)
- **Completed:** Font configuration (Settings view with native font picker, Cmd+/-/0)
- **Future:** Theme creation guide/documentation (lower priority)
- **Future:** User theme discovery from disk

## Impact
- Affected specs: theming (new)
- Affected code: VoidReaderCore (theme types), App/Views (editor, Settings, mermaid)
