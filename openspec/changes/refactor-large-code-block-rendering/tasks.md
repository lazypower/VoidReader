## 1. Core model
- [x] 1.1 Add `CodeSegment` value type (groupID, indexInGroup, totalInGroup, fullCode) to `VoidReaderCore`
- [x] 1.2 Extend `CodeBlockData` with optional `segment: CodeSegment?` (nil for non-segmented blocks)
- [x] 1.3 Add `CodeBlockData` helpers: `isSegmentFirst`, `isSegmentLast`, `isSegmented`

## 2. Renderer
- [x] 2.1 Add `BlockRenderer.segmentationLineThreshold` (initial value: 800 lines)
- [x] 2.2 `BlockRenderer.render` splits a code block whose line count exceeds the threshold into N segments joined by shared `groupID`
- [x] 2.3 Segmentation cuts on line boundaries; preserves original language and full code
- [x] 2.4 Unit tests for segmentation: exact-boundary, under-threshold, 2x, 10x threshold
- [x] 2.5 Unit test: `fullCode` round-trips (join of segment codes == original)

## 3. Measurement & cache
- [x] 3.1 `CodeBlockMeasurementKey` already hashes on `code` content — segments naturally produce distinct keys, no change needed
- [x] 3.2 `CodeBlockMeasurementScheduler` prefetch iterates segments in order (verified — each segment is a separate `.codeBlock` entry in `renderedBlocks`)
- [x] 3.3 `DocumentHeightIndex` records per-segment height; `configure` now accepts a `spacingProvider` so collapsed inter-segment seams don't drift the scroll-percent math

## 4. View layer
- [x] 4.1 `CodeBlockView` branches on `data.segment`:
  - first segment: badge + copy button, top corners rounded, bottom square
  - middle segment: no badge/copy, all corners square
  - last segment: no badge/copy, top square, bottom corners rounded
  - implemented via `data.isSegmentFirst` / `isSegmentLast` and `UnevenRoundedRectangle`
- [x] 4.2 Copy button on first segment copies `segment.fullCode` (not its local slice)
- [x] 4.3 `MarkdownReaderView` / `MarkdownReaderViewWithAnchors` / `ChunkView` collapse spacing between same-group adjacent segments via `BlockSpacing.topSpacing` (LazyVStack `spacing: 0` + per-row `.padding(.top, ...)`)
- [x] 4.4 No `maxRenderedHeight` / `allowsVerticalScroll` code path exists in the current tree (rejected before merge — nothing to remove)
- [x] 4.5 Keep `HorizontalOnlyScrollView` (per-segment wheel forwarding still correct)

## 5. Callers of block index
- [x] 5.1 Audit `MarkdownReaderViewWithAnchors.blockIndex(for:)` — scans `.text` blocks only; heading→block mapping unaffected because segments are `.codeBlock` entries and headings still live in their own `.text` block with the same text
- [x] 5.2 Audit `ContentView.headingForBlock(_:)` — resolves the last heading whose block index ≤ current; segmentation only *increases* indices of later blocks, so the "preceding heading" answer is unchanged
- [x] 5.3 Audit search match indexing — `blockIndexForMatch` iterates `.text` blocks only; code segments are not searched, so segmentation is a no-op for match→block mapping

## 6. Cleanup
- [x] 6.1 Remove diagnostic `DebugLog.log` calls added during the h=0 investigation (CodeBlockView `onAppear`/`onDisappear`/`requestMeasurement` internals; ContentView `prefetchCodeBlockMeasurements` per-block logs)
- [x] 6.2 Keep the `CodeBlockLayoutConfig.measureHeight` `withExtendedLifetime` fix (separate, merged concern)

## 7. Validation
- [x] 7.1 Open `Tests/.../fixtures/midsize_250k_code.md` — outer ScrollView scrolls cleanly top to bottom
- [x] 7.2 Scroll percentage climbs smoothly 0 → 100
- [x] 7.3 Copy button copies the entire 234KB Swift source (not just the first segment)
- [x] 7.4 Keyboard navigation (arrow, Page Down, Home/End) works across the code block
- [x] 7.5 Horizontal pan inside a segment still works on long lines
- [x] 7.6 Small code blocks (under threshold) render identically to pre-change
- [x] 7.7 Memory does not regress vs. pre-change on the 234KB fixture

## Follow-up (not blocking)
- Rapid-scroll stutter over segmented blocks. Architecture works; this is a
  profiling concern (measurement / highlight churn on fast row
  materialization). Park for a separate profiling pass.
