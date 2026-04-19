## Context
A single SwiftUI view with a frame taller than ~50k points silently breaks
hit-testing for the enclosing `ScrollView`. We hit this when rendering real
source files as code fences: a 234KB Swift file measures at 114,784pt. The
viewport's scroll wheel, scroll bar, and keyboard navigation all stop working
as long as that child view is in the tree. Capping the displayed height
papers over the symptom but misrepresents the document to the scroll-percent
math and fragments the UX (user has to scroll-inside-then-back-outside).

The right abstraction: a code block is not a single view, it's a sequence of
renderable segments that present as one visual block. This matches how
`LazyVStack` wants to be fed (many small rows) and how AppKit/TextKit
measurement scales (per-segment cost, parallelizable).

## Goals / Non-Goals

### Goals
- Arbitrarily large code blocks render correctly and do not break outer
  scroll, keyboard, or scrollbar interaction.
- Segmentation is invisible to the reader: continuous background, one
  language badge, one copy button that copies the entire original code.
- Per-segment measurement and highlighting are cached individually, so
  reopening a document pays no re-measurement cost for segments whose
  content hash is unchanged.
- Scroll-percentage math continues to track the visible document accurately.

### Non-Goals
- Do not add in-block vertical scrolling. The whole document flows.
- Do not word-wrap long lines. Horizontal overflow continues to pan inside
  each segment (inherited from existing `CodeTextView`).
- Do not change the parsed `MarkdownBlock` *contract* for small code blocks
  that fit under the segmentation threshold — they remain a single block.
- Do not make segmentation visible in outline / headings / search indexing.

## Decisions

### Decision: Segmentation happens at `BlockRenderer`, not in the view
`BlockRenderer` already owns the conversion from parsed markdown to the
`[MarkdownBlock]` array the view consumes. Splitting at that layer keeps the
view layer a pure renderer and means every consumer of the block list
(scroll percent, outline, search, measurement prefetch) sees the same
segmented structure without special-casing.

**Alternatives considered:**
- *View-layer splitting inside `CodeBlockView`*: rejected — the view can't
  emit multiple rows into the parent's `LazyVStack`, so it would require a
  different wrapping abstraction and would hide segment identity from search
  and scroll.
- *Post-parse transformation in `ContentView.updateRenderedBlocks`*:
  rejected — duplicates logic the renderer already owns and would need to
  re-apply anywhere blocks are generated (e.g. future preview, tests).

### Decision: Segment metadata travels on `CodeBlockData`
Add optional segment metadata to `CodeBlockData`:
```
struct CodeSegment {
    let groupID: UUID           // shared across segments of one logical block
    let indexInGroup: Int       // 0-based
    let totalInGroup: Int
    let isFirst: Bool           // == indexInGroup == 0
    let isLast: Bool            // == indexInGroup == totalInGroup - 1
    let fullCode: String        // original un-split code (for copy)
}
```
Non-segmented code blocks leave this `nil`. `CodeBlockView` branches on
presence: first segment renders the badge + copy button; inner segments
render only their slice; the last segment rounds its bottom corners.

**Alternatives considered:**
- *Separate `.codeSegment(...)` block case*: rejected — doubles every
  switch over `MarkdownBlock` and makes small-block code paths handle two
  types unnecessarily.
- *Carry only `fullCode` on the first segment*: rejected — the copy button
  fires from the first segment only anyway, but stashing it on every
  segment is cheap (reference to the same String) and lets us move the
  button later without reshuffling data.

### Decision: Segment boundary is line-based, target ~800 lines / ~2000 pt
Line-based keeps segments self-contained syntax units for highlighter
coalescing and avoids splitting mid-token. At typical code font metrics
(~16pt line height), 800 lines is ~12,800 pt per segment — well under any
plausible hit-test ceiling, still large enough that typical code files
remain one segment and segmentation only kicks in for the pathological
case. The threshold lives in one place; segment count is
`ceil(lineCount / 800)`.

**Alternatives considered:**
- *Height-based boundary* (e.g. target 3000pt per segment): rejected —
  requires measurement before we know where to cut, which is the reason we
  measure in the first place. Line count is a cheap proxy.
- *Dynamic threshold based on viewport*: rejected — complexity without
  payoff; the fixed number of lines is already generous.

### Decision: Visual continuity via shared background + conditional corners
Today `CodeBlockView` wraps content in a single rounded rectangle. For
segments:
- First segment: top corners rounded, bottom square, badge + copy button
- Middle segments: all corners square, no badge/copy, no top/bottom padding
- Last segment: bottom corners rounded, no badge/copy, no top padding
Background color and horizontal insets are identical, so adjacent segments
appear as one continuous block. The 16pt inter-block spacing that
`LazyVStack` adds between ordinary blocks must **not** appear between
segments of the same group; the reader view collapses spacing when the
next block is a same-group continuation.

## Risks / Trade-offs

- **Risk**: `LazyVStack` spacing between segments shows as visible seams.
  *Mitigation*: reader view detects same-group adjacency and renders
  segments in an inner `VStack(spacing: 0)`, pushing the 16pt between the
  group and its neighbors only. Covered by a rendering test.

- **Risk**: Copy-whole-block from the first segment desyncs if a later
  segment's `fullCode` diverges (shouldn't happen but defensive).
  *Mitigation*: `fullCode` is generated once at segmentation time and
  shared by reference across every segment in the group; equality is a
  pointer comparison.

- **Risk**: Search result ranges that previously referenced one block now
  reference N, breaking "block index of match" callers (outline sync,
  jump-to-heading).
  *Mitigation*: existing callers use `blockIndex` which is now a segment
  index — numerically different but semantically the same "which row am I
  on." Audit the two callers:
  `MarkdownReaderViewWithAnchors.blockIndex(for:)` and
  `ContentView.headingForBlock(_:)`. Headings come from a prior block to
  the code block in practice, so segmentation doesn't split a heading.

- **Trade-off**: Measurement cache grows by ~N× for segmented blocks.
  Acceptable — each segment's attributed string is 1/N the size, so total
  memory is roughly unchanged; the tradeoff is more cache keys, not more
  bytes.

## Migration Plan
No user-visible migration. Old cache entries (keyed on full-block content
hash) simply miss on first open after upgrade; the new keys (per-segment
content hash) repopulate on the prefetch. No document changes; no disk
state changes.

## Open Questions
- Does `swift-markdown`'s `CodeBlock.range` give us per-line source
  positions we can use to align segment boundaries with original-file
  line numbers (for future "goto line" in code blocks)? Leave as a
  follow-up; initial segmentation uses newline-split which is correct
  for render but not source-aligned.
- Should we expose segment boundaries in search index so a search spanning
  a segment boundary still matches? Deferred — search is full-doc scan
  today, not per-block.
