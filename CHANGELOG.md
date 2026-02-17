# Changelog

All notable changes to VoidReader. We actually read markdown here.

---

## [0.3.0] - 2026-02-16

### The Judgmental Release

VoidReader now has opinions about your markdown. Strong ones.

#### Added

- **Markdown Linter** - 8 rules to keep your docs respectable
  - MD001: Headings should increment by one (no skipping leg day)
  - MD004: Pick a list marker and commit to it
  - MD009: Trailing whitespace is not a personality trait
  - MD012: One blank line is enough, we get it
  - MD022: Headings need breathing room
  - MD026: Headings aren't sentences, drop the punctuation
  - MD031: Code blocks deserve personal space too
  - MD049: Emphasis markers should be consistent (pick * or _)

- **Markdown Formatter** - Auto-fix for the chaos
  - Format Document (Cmd+Shift+I) for on-demand tidying
  - Format on Save toggle for the disciplined
  - Normalizes list markers, emphasis, whitespace
  - Aligns table columns like a civilized editor
  - Adds blank lines where they belong

- **Warning Badge** in status bar - know your shame at a glance

#### Fixed

- Font size slider now updates reader view (not just code blocks, whoops)
- No more false "document modified" prompts on syntax highlight
- Smoother edit mode transitions via debounced rendering
- Swift compiler no longer times out on our onChange handlers

---

## [0.2.0] - 2026-02-16

### The "Actually Useful" Release

VoidReader grows up. Images render, math compiles, themes exist.

#### Added

- **Image Support** - Finally, pictures
  - Local and remote image loading with async magic
  - Disk cache for remote images (24h expiry, we're not animals)
  - Click-to-expand with zoom/pan overlay
  - Supports PNG, JPG, GIF, WebP, SVG

- **LaTeX Math Rendering** - For the academics
  - Block math with `$$...$$` via bundled KaTeX
  - Themed to match your color scheme
  - Graceful fallback on syntax errors

- **Theme System** - Because dark mode isn't optional
  - System theme (native macOS semantic colors)
  - Catppuccin Mocha (dark) / Latte (light)
  - Runtime theme loading from `~/Library/Application Support/VoidReader/Themes/`
  - Syntax highlighting follows your theme

- **Signed Distribution** - macOS trusts us now

#### Fixed

- Smooth viewport transitions that feel native
- Mermaid diagrams scale properly on retina displays

---

## [0.1.0] - 2026-02-15

### Hello, Void

The beginning. A markdown viewer that doesn't hate you.

#### Added

- **Native Markdown Rendering** - No web views for text (Mermaid gets a pass)
  - Full GFM support: tables, task lists, strikethrough
  - Clickable task checkboxes that actually update the file
  - Code blocks with one-click copy
  - Syntax highlighting via AttributedString

- **Edit Mode** - Split-pane editing for when reading isn't enough
  - Live preview that keeps up
  - GFM cheat sheet (hold Cmd+Shift+?)
  - Distraction-free mode (Cmd+Shift+F)
  - Status bar with word count, character count, reading time

- **Mermaid Diagrams** - Flowcharts in your markdown
  - Bundled mermaid.min.js (no Node runtime needed)
  - Click-to-expand fullscreen view
  - Graceful fallback to code on render failure

- **Navigation** - Find your way
  - Outline sidebar (Cmd+Shift+O)
  - Find & Replace (Cmd+F / Cmd+H)
  - Match highlighting in reader view

- **Document Handling** - The basics, done right
  - Quick Look preview extension
  - Print and Export to PDF
  - File watching with external change detection
  - Font size controls (Cmd++/-/0)
  - Settings with native font picker

- **App Icon** - A void gradient that sparks joy

---

## The Void Awaits

Built for people who actually read markdown. No Electron. No web views for text. Just your documents, rendered beautifully.
