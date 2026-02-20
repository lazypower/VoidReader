# Change: Optimize Large Document Performance

## Why
Large markdown documents exhibit sluggish scrolling and editor responsiveness. Post-1.0 optimization pass to ensure the app scales gracefully with document size.

**Target**: 50,000 lines (~2.5MB) with 60fps scrolling and responsive editing.

## What Changes

### Core Architecture Change
- **Virtual scrolling**: Render only visible blocks + buffer, not entire document
  - Constant memory usage regardless of document size
  - Constant render cost regardless of document size
  - Enables true "unlimited" document support

### Supporting Optimizations
- **Scroll tracking refactor**: Replace per-block GeometryReader with single scroll observer
- **Syntax highlighter optimization**: Cache line offsets to eliminate O(n²) behavior
- **State cascade consolidation**: Remove duplicate renders, add debouncing to search
- **Debounce tuning**: Increase editor highlight debounce from 150ms to 200ms

### Phased Rollout
Each phase is validated before proceeding to next. Allows rollback to last known good state.

## Impact
- Affected specs: `markdown-rendering` (MODIFIED: performance requirements)
- Affected code:
  - `App/Views/MarkdownReaderView.swift` - virtual scrolling, scroll tracking
  - `App/Views/ContentView.swift` - state management, block windowing
  - `App/Views/SyntaxHighlightingEditor.swift` - highlight debounce, visible-region highlighting
  - `Sources/VoidReaderCore/Theming/MarkdownSyntaxHighlighter.swift` - line offset cache
  - `Sources/VoidReaderCore/Renderer/BlockRenderer.swift` - block height estimation

## Research Summary

### Root Causes Identified

| Issue | Location | Severity |
|-------|----------|----------|
| GeometryReader per block | MarkdownReaderView:102-109 | HIGH |
| O(n) charOffset per AST node | MarkdownSyntaxHighlighter:216-236 | HIGH |
| Double render on font change | ContentView:301-314 + 212-214 | MEDIUM |
| Undbounced search counting | ContentView:203-204 | MEDIUM |
| Duplicate subscription setup | ContentView:152-154 + 163 | LOW |

### Scroll Tracking Deep Dive

**Current approach** (lines 102-109 in MarkdownReaderView.swift):
```swift
ForEach(Array(renderBlocks.enumerated()), id: \.offset) { index, block in
    BlockView(...)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: BlockPositionPreferenceKey.self,
                    value: [index: geo.frame(in: .named("reader-scroll")).minY]
                )
            }
        )
}
```

For a 500-block document, this creates 500 GeometryReaders, each reporting position via preference key on every scroll frame at 120Hz. The `onPreferenceChange` callback then filters and finds max across all positions.

**Data is used for**:
1. Outline sidebar sync (`currentTopBlockIndex` -> `selectedHeadingID`)
2. Progress indicator (`displayedPercentRead` in status bar)
3. Edit mode scroll restore (`savedScrollBlockIndex`)

**Proposed approach**:
- Single GeometryReader at top tracking scroll offset
- Pre-compute cumulative block heights during render
- Binary search to find visible block from offset
- Debounce the lookup (50-100ms)

### Syntax Highlighting Deep Dive

**Current approach** (MarkdownSyntaxHighlighter.swift:216-236):
```swift
private func charOffset(from loc: SourceLocation) -> Int? {
    var offset = 0
    var currentLine = 1
    for char in source {
        if currentLine == loc.line {
            return offset + (loc.column - 1)
        }
        if char == "\n" { currentLine += 1 }
        offset += 1
    }
    // ...
}
```

Called once per AST node during highlighting. For a syntax-heavy document with M nodes in an N-character document, this is O(N*M) approaching O(N^2).

**Proposed approach**:
```swift
// Build once: O(n)
var lineOffsets: [Int] = [0]
for (i, char) in source.enumerated() {
    if char == "\n" { lineOffsets.append(i + 1) }
}

// Lookup: O(1)
func charOffset(from loc: SourceLocation) -> Int {
    guard loc.line <= lineOffsets.count else { return nil }
    return lineOffsets[loc.line - 1] + (loc.column - 1)
}
```

### State Cascade Analysis

**Font size change flow** (ContentView.swift):
1. `increaseFontSize()` called (line 301)
2. Updates `@AppStorage("readerFontSize")`
3. Calls `updateRenderedBlocks()` directly (line 303)
4. ALSO triggers `renderTrigger` onChange (line 212)
5. Which calls `updateRenderedBlocks()` again = double render

**Search update flow**:
- `searchText` onChange triggers `updateSearch()` immediately
- `updateSearch()` calls `countMatchesInRenderedBlocks()`
- Walks entire block tree per keystroke
- No debouncing

## Non-Goals
- Incremental parsing (re-parse only changed blocks) - complexity vs benefit unclear
- Background thread block rendering - SwiftUI view construction must be main thread
- Memory-mapped file reading - overkill for markdown text files
- Streaming parser - swift-markdown doesn't support, would require custom parser

## Risk Mitigation
- **Phased rollout**: Each phase validated independently
- **Feature preservation**: All existing features (outline sync, scroll restore, search) must work
- **Performance regression tests**: Establish baselines, measure after each phase
- **Rollback plan**: Each phase can be reverted without affecting others
