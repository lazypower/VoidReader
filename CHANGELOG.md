# Changelog

All notable changes to VoidReader. We actually read markdown here.

---

## [1.2.1] - 2026-07-08

### The "Trust Issues" Release

A cold-eyes audit found the oldest third of the codebase quietly corrupting files, crashing on print, and shipping math in the wrong font. No new features — just VoidReader doing what it already claimed to do, correctly.

#### Fixed

- **Format-on-save no longer rewrites code fences** - stopped mangling YAML markers, `__init__`, and shell pipelines-as-tables inside code blocks; stopped deleting emoji table cells (subsystem went from 0 tests to a torture suite)
- **Find & Replace edits what you see** - it counted rendered matches but replaced raw text, so a replace could hit an unseen occurrence (even in a code fence). Now one consistent universe, or it refuses
- **Task checkboxes toggle the item you clicked** - across multiple lists and `*`/`+` markers
- **Two crashes** - Mermaid print/export double-resume; FileWatcher use-after-free
- **Math renders in the bundled KaTeX fonts** - it had been falling back to serif in every shipped build
- **Quick Look loads** (the extension is sandboxed now) and **signed builds keep their entitlements**
- Raw HTML preserved (`<kbd>`, `<details>`), blockquote paragraphs no longer fuse, `[**bold**](url)` stays clickable, "$5 and $10" isn't math, `$$` inside a fence stays put, duplicate heading anchors deduped
- Editor theme no longer reverts on the next keystroke; split divider tracks the cursor; scroll position restored; own-saves no longer nag a reload
- Image cache stops serving the wrong picture for similar CDN URLs; ~450 LOC of dead code removed; MD009/MD012 respect fences; MD049 split into MD049/MD050

#### The Numbers

- ~30 fixes across correctness, crashes, packaging, rendering, editor, and cleanup
- 149 → 191 core tests
- Every change cross-model reviewed, then vibe-checked in the running app

---

## [1.2.0] - 2026-04-26

### The "Reading the Fine Print" Release

VoidReader now reads your YAML frontmatter so you don't have to.

#### Added

- **Frontmatter Banner** - YAML frontmatter (`---` fenced at the top) renders as a styled banner: labeled key-value rows, comma-separated values wrapped into pills. Works in the reader, print output, and Quick Look

#### Fixed

- Scroll percentage no longer reads 100% instantly on large documents - 1.1's progressive rendering calculated it against the initial chunk's height; now recalculated when the full-document height lands

#### Housekeeping

- Centralized the code-block chrome constants into one place; regression + UI tests keeping the scroll math honest

---

## [1.1.0] - 2026-04-21

### The "We Measure Twice Now" Release

Instrument first, optimize second. We built a performance lab and let the profile pick the fixes, in order, with receipts.

#### Added

- **Performance lab** - pathological fixtures (100k code block, 250k mixed, 50k table) run through `xctrace` in CI with baseline gating; OSSignposter across document lifecycle, rendering, and the image/mermaid/scroll subsystems

#### Performance

- **134x faster large-doc load** (1,475ms → 11ms for a 60k-line doc) via progressive rendering
- Off-main measurement cache for code blocks (Highlightr's JSContext is thread-pinned, which shaped the design)
- Document-wide cumulative height index for scroll math instead of asking each block
- Large code blocks segmented across virtualized rows; tables pre-measure and virtualize
- Search stopped walking the whole document per keystroke (dropped an O(M·N) line-count; cached result previews)

---

## [1.0.4] - 2026-03-04

### The "Math Is Hard" Release

Turns out not every block is 60 pixels tall.

#### Fixed

- Scroll percentage uses real measured heights instead of `blockCount × 60px`, so it stops confidently claiming 100% right past the introduction. Extracted `ScrollPercentage.calculate()` into VoidReaderCore with 9 unit + 4 UI tests

---

## [1.0.3] - 2026-02-26

### The "Scroll Like You Mean It" Release

The one where diagrams stop cosplaying as thumbnails.

#### Fixed

- Mermaid diagrams scale to fill the reading width (proper vector scaling) instead of rendering ant-sized
- Tables switched to `Grid` - killed the N² nested VStack/HStack/ForEach layout that stalled table scrolling
- Code blocks highlight once and cache, instead of re-running Highlightr on every frame during scroll
- Failed mermaid diagrams cache the failure and show a code fallback instead of retrying every scroll pass

#### Added

- Automated release pipeline - push a tag, GHA builds, signs, notarizes, releases, and updates the Homebrew cask

---

## [1.0.1] - 2026-02-19

### The "Whoops, Maybe Test With Big Files" Release

Someone opened a 50,000-line markdown file and VoidReader contemplated the meaning of life for about 90 seconds. Our bad.

#### Performance

- Progressive rendering (first ~20KB immediately, rest in the background), LazyVStack virtualization, chunked rendering for >1000-block docs, visible-region editor highlighting, cached `InlineMathParser` regex, debounced scroll tracking

#### Fixed

- Read percentage re-enabled and tracks scroll continuously (the GeometryReader has to live *outside* the LazyVStack to fire during scroll)

#### Added

- Debug telemetry (`VOID_READER_DEBUG=1`), file logging, XCUITest infrastructure, `make run-debug`

---

## [1.0.0] - 2026-02-17

### The "We Actually Shipped" Release

VoidReader is complete. Every feature polished. Every pixel considered.

#### Added

- **Custom Document Icon** - Galaxy-themed beauty for your .md files (designed by Fiona)
- **Reader Theming Toggle** - Apply theme to reader view, or keep it native macOS
- **Inline Math Rendering** - `$...$` now renders with styled monospace text
- **Images in Print/PDF** - Document images and mermaid diagrams render in exports
- **Paginated PDF Export** - Proper multi-page output with intelligent page breaks

#### Fixed

- Blocks no longer get guillotined at page boundaries
- Theme toggle updates reader view immediately
- PDF export uses vector rendering via NSPrintOperation

#### The Numbers

- 9 OpenSpec capabilities: all complete
- 0 Electron: as promised
- 1 beautiful app: shipped

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
