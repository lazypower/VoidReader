# VoidReader Design Philosophy

## Core Identity

VoidReader is a **focused, elegant markdown reader** for macOS. The visual language reflects:

- **The Void**: Deep space, calm emptiness, room to think
- **Clarity**: Content-first, distraction-free
- **Native feel**: Respects macOS conventions while having distinct personality

## Color Palette

### Reader View (Native macOS)

Uses semantic system colors for automatic light/dark adaptation:
- `NSColor.textColor` / `NSColor.textBackgroundColor`
- Respects user's accent color and accessibility settings

### Editor Syntax (Catppuccin)

- **Dark (Mocha)**: Base `#1e1e2e`, Text `#cdd6f4`
- **Light (Latte)**: Base `#eff1f5`, Text `#4c4f69`
- Accent colors: mauve, blue, green, teal, lavender

### App Icon / Brand

- Deep void gradient: purples and blues
- Cosmic nebula texture
- "VR" letterforms emerging from the void
- Subtle starfield at high resolution

## Document Icons

### Base Icon (`.md` / `.markdown`)

- macOS document shape (rounded rect, optional folded corner)
- Void aesthetic as "page content" - deep space gradient
- Subtle markdown hint (`#` or `VR` monogram)
- Must be recognizable at 16px, detailed at 1024px

### Badge Variants

| Type    | Badge           | Color    | Use Case                  |
| ------- | --------------- | -------- | ------------------------- |
| Mermaid | Flowchart nodes | Teal     | Files with mermaid blocks |
| Math    | Σ or ∫ symbol   | Lavender | Files with LaTeX math     |

## Typography

- **Reader**: User-configurable, defaults to system serif
- **Editor**: Monospace (user-configurable)
- **UI Chrome**: SF Pro (system default)

## Interaction Principles

1. **Content is king** - UI fades when not needed
2. **Keyboard-first** - Full navigation without mouse
3. **No surprises** - Standard macOS patterns (Cmd+S, Cmd+P, etc.)
4. **Smooth transitions** - Subtle animations, never jarring

## What We Avoid

- Bright/garish colors that fight for attention
- Skeuomorphic decoration
- Animations that delay the user
- UI that requires explanation
- Deviation from HIG without clear benefit

## Icon Sizes (Technical)

For `.icns` generation:

```
16x16, 32x32, 64x64, 128x128, 256x256, 512x512, 1024x1024
(@ 1x and 2x retina)
```

Asset catalogs preferred for Xcode integration.
