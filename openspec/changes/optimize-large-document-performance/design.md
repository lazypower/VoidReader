# Design: Large Document Performance Optimization

## Context

VoidReader hit 1.0. Time for an aggressive optimization pass to ensure the app scales gracefully with document size.

**Target**: 50,000 lines (~2.5MB) with 60fps scrolling and responsive editing.

**Stakeholders**: Users with large markdown files - technical docs, knowledge bases, exported notes.

**Constraints**:
- Must maintain all existing features (outline sync, scroll restore, search, progress indicator)
- Phased rollout - each phase validated before proceeding
- SwiftUI-native where possible (avoid AppKit unless necessary)

## Goals / Non-Goals

### Goals
- 60fps scrolling on 50,000-line documents
- Sub-200ms editor responsiveness during continuous typing
- Constant memory usage regardless of document size (within view layer)
- All existing features preserved

### Non-Goals
- Incremental parsing (complexity vs benefit unclear)
- Streaming/partial file loading (markdown files are text, not gigabytes)
- Custom parser (swift-markdown is fast enough)

## Core Decision: Virtual Scrolling

### What
Render only visible blocks + buffer zone, not entire document. Use `LazyVStack` with estimated heights and measured adjustments.

### Why
This is the single architectural change that enables true scalability:
- Current: O(N) views in hierarchy for N blocks
- Virtual: O(1) views (visible + buffer, ~50-100 blocks max)

With virtual scrolling:
- 500 blocks and 50,000 blocks have identical scroll performance
- Memory stays constant regardless of document size
- Initial render is instant (only visible content)

### SwiftUI Approach

```swift
// Current: All blocks rendered
ScrollView {
    VStack {
        ForEach(blocks) { block in BlockView(block) }  // N views
    }
}

// Virtual: Only visible blocks rendered
ScrollView {
    LazyVStack(spacing: 16) {
        ForEach(blocks) { block in
            BlockView(block)
                .frame(minHeight: estimatedHeight(for: block))
        }
    }
}
```

**LazyVStack behavior**:
- SwiftUI creates views on-demand as they scroll into view
- Views are recycled when scrolling out of view
- We provide height estimates to enable smooth scrollbar behavior

### Block Height Strategy

Variable block heights are the hard part. Options:

| Strategy | Pros | Cons |
|----------|------|------|
| Fixed estimate per type | Simple, predictable | Jumpy scrollbar on content mismatch |
| Measure on first render | Accurate after seen | Slight jump on first scroll through |
| Pre-compute from content | Most accurate | CPU cost upfront |

**Decision**: Measure on first render with reasonable type-based estimates.

```swift
struct BlockHeightCache {
    var estimates: [MarkdownBlock.BlockType: CGFloat]  // Type defaults
    var measured: [Int: CGFloat]  // Block index -> actual height

    func height(for block: MarkdownBlock, at index: Int) -> CGFloat {
        measured[index] ?? estimates[block.type] ?? 44  // Default line height
    }

    mutating func record(index: Int, height: CGFloat) {
        measured[index] = height
    }
}
```

### Scroll Position Tracking

With LazyVStack, we lose per-block GeometryReader tracking (good - that was a perf killer). New approach:

1. **Single scroll offset observer** at container level
2. **Binary search** through cumulative height index to find visible block
3. **Debounced updates** to outline sync (50ms)

```swift
func findVisibleBlock(scrollOffset: CGFloat, heights: BlockHeightCache) -> Int {
    var cumulative: CGFloat = 0
    for (index, height) in heights.allHeights.enumerated() {
        cumulative += height
        if cumulative > scrollOffset { return index }
    }
    return heights.count - 1
}
```

### Search in Virtual Context

Current search highlights matches in all blocks. With virtual scrolling:
- Only visible blocks need highlighting applied
- Match index -> block index lookup pre-computed
- "Jump to match" scrolls to block, which triggers render

```swift
struct SearchIndex {
    var matchesByBlock: [Int: [Range<String.Index>]]  // Block index -> matches
    var matchToBlock: [Int]  // Global match index -> block index

    func blockForMatch(_ matchIndex: Int) -> Int {
        matchToBlock[matchIndex]
    }
}
```

## Supporting Decisions

### Decision 2: Line Offset Cache in Highlighter

**What**: Build line-to-character-offset lookup table once per highlight pass.

**Why**: Current `charOffset()` scans from start for every AST node. O(N*M) → O(N+M).

```swift
let lineOffsets: [Int] = source.indices
    .filter { source[$0] == "\n" }
    .map { source.distance(from: source.startIndex, to: $0) + 1 }
    .prepending(0)

func charOffset(line: Int, column: Int) -> Int {
    lineOffsets[line - 1] + (column - 1)
}
```

### Decision 3: Visible-Region Editor Highlighting

**What**: In editor, only apply syntax highlighting to visible text region + buffer.

**Why**: Full-document highlighting on every keystroke is expensive. Most edits are local.

```swift
func rehighlight(_ textView: NSTextView) {
    let visibleRange = textView.visibleCharacterRange()
    let bufferRange = visibleRange.expanded(by: 1000)  // ±1000 chars

    // Parse full doc (fast), but only apply attributes to visible region
    let highlighted = highlighter.highlight(source, applyingTo: bufferRange)
    textStorage.setAttributes(highlighted, range: bufferRange)
}
```

**Tradeoff**: Off-screen text won't have highlighting until scrolled into view. Acceptable - user can't see it anyway.

### Decision 4: State Cascade Consolidation

**What**: Remove duplicate render triggers, debounce search.

**Changes**:
1. Remove direct `updateRenderedBlocks()` from font size functions
2. Add 100ms debounce to search via Combine
3. Guard `setupDebouncing()` against duplicate subscriptions

## Implementation Phases

### Phase 1: Foundation (Low Risk)
- Fix state cascade issues (double render, search debounce)
- Add line offset cache to syntax highlighter
- Increase editor debounce to 200ms
- Establish performance baselines

**Verification**: Profile scrolling/editing, compare to baseline

### Phase 2: Virtual Reader (Medium Risk)
- Convert MarkdownReaderView to LazyVStack
- Implement block height cache with type estimates
- Add single scroll offset observer
- Update outline sync to use binary search

**Verification**:
- 50K line doc scrolls at 60fps
- Outline sidebar still syncs
- Progress indicator works
- Search jump-to-match works

### Phase 3: Virtual Editor Preview (Medium Risk)
- Apply same virtualization to edit mode preview pane
- Implement visible-region highlighting for editor
- Ensure scroll sync between editor and preview

**Verification**:
- Editor responsive on 50K line doc
- Preview updates correctly
- Split pane scroll sync works

### Phase 4: Polish & Edge Cases
- Handle rapid scroll (scrollbar drag)
- Optimize block height estimation
- Memory profiling and cleanup
- Performance regression test suite

**Verification**:
- No memory leaks on repeated open/close
- Rapid scrolling doesn't cause jank
- All existing tests pass

## Risks / Mitigations

| Risk | Mitigation |
|------|------------|
| LazyVStack doesn't play nice with scroll position | Fall back to manual virtualization with GeometryReader |
| Block height estimates cause jumpiness | Measure eagerly on initial render pass |
| Search highlighting in virtual context is tricky | Pre-compute search index, apply to visible blocks only |
| Outline sync accuracy degrades | Use heading blocks only (semantically meaningful, fewer) |
| Edit mode scroll restore breaks | Store block index, use scrollTo after lazy render |

## Open Questions

1. **LazyVStack + ScrollViewReader compatibility**: Does `scrollTo(id:)` work with lazy views?
   - Need to test - if not, may need custom scroll positioning

2. **Mermaid/Math block heights**: These render async in WebView - how to estimate?
   - Start with generous estimate (300pt), measure after render

3. **Search performance on 50K lines**: Is search itself fast enough?
   - TextSearcher uses String.range() - profile on large doc

## Performance Targets

| Metric | Current (1K lines) | Target (50K lines) |
|--------|-------------------|-------------------|
| Initial render | ~200ms | <500ms |
| Scroll FPS | 30-45fps | 60fps |
| Keystroke latency | ~150ms | <100ms |
| Memory (view layer) | ~50MB | <100MB |
