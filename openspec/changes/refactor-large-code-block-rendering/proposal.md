# Change: Render large code blocks as a sequence of segments

## Why
A single fenced code block that lays out taller than SwiftUI `ScrollView`'s
hit-testing tolerates (empirically ~50k points; a 234KB Swift file measures at
~115k points) silently breaks scrolling for the entire document — mouse wheel,
trackpad, scroll-bar drag, and keyboard navigation all go dead.

The root cause is structural: we're asking SwiftUI to hit-test a single child
view whose frame exceeds the viewport by two orders of magnitude. Capping the
rendered height is a hack that misrepresents the document to the scroll-percent
math and the reader UX.

The fix is to stop handing `LazyVStack` a pathologically tall single row.
A code block becomes a *sequence of renderable segments* that share styling,
background, and copy behavior — one visual block made of many small rows.

## What Changes
- `MarkdownBlock.codeBlock` renderer splits large code blocks into N segments
  at line boundaries below a safe per-segment height budget.
- Segments carry enough identity (group id, position within group, total
  count) that the view layer can render a **continuous** visual block:
  shared language badge on the first segment, copy button on the first
  segment copies the *full* original code, seamless backgrounds with rounded
  corners only on the leading/trailing segments.
- `CodeBlockView` grows a segment-aware mode: a segment is still an
  `NSTextView`-backed row, but each is short enough that the outer SwiftUI
  `ScrollView` stays healthy and each row can forward vertical wheel events
  up naturally.
- `DocumentHeightIndex` and the measurement cache operate per-segment, so
  scroll percentage and prefetch both stay accurate and local.
- No user-visible change for code blocks that already fit under the cap.

## Impact
- Affected specs: `markdown-rendering` (ADDED: Large Code Block Segmentation)
- Affected code:
  - `Sources/VoidReaderCore/Renderer/BlockRenderer.swift` — segment splitting
  - `Sources/VoidReaderCore/Models/MarkdownBlock.swift` (or equivalent) —
    segment metadata on `CodeBlockData`
  - `App/Views/CodeBlockView.swift` — segment-aware rendering, shared
    identity across rows, copy-entire-block behavior
  - `App/Views/MarkdownReaderView.swift` — no change expected; segments flow
    as ordinary `LazyVStack` rows
  - `App/Rendering/CodeBlockMeasurementCache.swift` — per-segment keys
  - `App/Views/ContentView.swift` — prefetch loop iterates segments
