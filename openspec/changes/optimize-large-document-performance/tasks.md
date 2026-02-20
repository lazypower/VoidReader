# Tasks: Large Document Performance Optimization

**Target**: 50,000 lines with 60fps scrolling and responsive editing.

## 0. Setup & Baselines

- [x] 0.1 Create 50K line test document (varied content: headings, code, tables, lists)
- [ ] 0.2 Measure baseline scroll FPS on test document
- [ ] 0.3 Measure baseline keystroke latency in editor
- [ ] 0.4 Measure baseline memory usage
- [ ] 0.5 Document baseline metrics for comparison

## 1. Phase 1: Foundation (Low Risk)

### 1.1 State Cascade Fixes
- [x] 1.1.1 Remove direct `updateRenderedBlocks()` call from `increaseFontSize()` (ContentView.swift:303)
- [x] 1.1.2 Remove direct `updateRenderedBlocks()` call from `decreaseFontSize()` (ContentView.swift:308)
- [x] 1.1.3 Remove direct `updateRenderedBlocks()` call from `resetFontSize()` (ContentView.swift:313)
- [x] 1.1.4 Add guard to `setupDebouncing()` to prevent duplicate subscriptions
- [x] 1.1.5 Consolidate duplicate `onAppear` blocks (lines 152-154 and 163-167)

### 1.2 Search Debouncing
- [x] 1.2.1 Add `searchUpdatePublisher` PassthroughSubject to ContentView
- [x] 1.2.2 Wire search text/options changes to publisher instead of direct `updateSearch()` calls
- [x] 1.2.3 Add 100ms debounce in `setupDebouncing()` for search publisher
- [ ] 1.2.4 Test search still works correctly with debounce

### 1.3 Syntax Highlighter Optimization
- [x] 1.3.1 Add `lineOffsets: [Int]` property to `SyntaxColorWalker` struct
- [x] 1.3.2 Build line offset table in `SyntaxColorWalker.init()`
- [x] 1.3.3 Refactor `charOffset(from:)` to use cached offsets (O(1) lookup)
- [x] 1.3.4 Remove old linear scan implementation
- [x] 1.3.5 Increase `highlightTimer` interval from 0.15 to 0.20 (SyntaxHighlightingEditor.swift:121)
- [x] 1.3.6 Cache InlineMathParser regex (avoid recompilation on every call)

### 1.4 Phase 1 Verification
- [x] 1.4.1 Run existing tests
- [ ] 1.4.2 Measure scroll FPS improvement
- [ ] 1.4.3 Measure keystroke latency improvement
- [ ] 1.4.4 Document Phase 1 metrics

## 2. Phase 2: Virtual Reader (Medium Risk)

### 2.1 Block Height Infrastructure
- [x] 2.1.1 Create `BlockHeightCache` struct in VoidReaderCore
- [x] 2.1.2 Add `BlockType` property to `MarkdownBlock` enum if not present
- [x] 2.1.3 Define default height estimates per block type
- [x] 2.1.4 Implement height lookup with estimate fallback
- [x] 2.1.5 Add method to record measured height

### 2.2 LazyVStack Migration
- [x] 2.2.1 Replace `VStack` with `LazyVStack` in `MarkdownReaderView`
- [x] 2.2.2 Add `.frame(minHeight:)` using height estimates
- [x] 2.2.3 Add GeometryReader wrapper to measure actual heights
- [x] 2.2.4 Store measured heights in cache
- [x] 2.2.5 Keep block `.id("block-\(index)")` for ScrollViewReader
- [x] 2.2.6 Add chunked virtualization for docs >1000 blocks (100 blocks/chunk)

### 2.3 Scroll Position Tracking
- [x] 2.3.1 Create `ScrollOffsetKey` preference key for single offset value
- [x] 2.3.2 Add single GeometryReader at top of LazyVStack
- [x] 2.3.3 Remove per-block GeometryReader backgrounds
- [x] 2.3.4 Implement `findVisibleBlock(scrollOffset:)` using cumulative heights
- [x] 2.3.5 Add 200ms debounce to scroll position updates
- [x] 2.3.6 Replace inline closures with method references (prevents view invalidation)

### 2.4 Async Block Rendering
- [x] 2.4.0 Move BlockRenderer.render() to background thread for large docs (>50K chars)
- [x] 2.4.1 Add loading indicator ("Rendering document...") during async render
- [x] 2.4.2 Guard scroll restoration until rendering completes
- [x] 2.4.3 Move updateHeadings() to background thread for large docs
- [x] 2.4.4 Progressive rendering: show first ~20KB immediately, render rest in background
  - Result: 11ms to first content (134x faster than monolithic 1475ms)

### 2.4 Outline Sync Update
- [x] 2.4.1 Update `onTopBlockChange` callback to use new tracking
- [x] 2.4.2 Update `onScrollProgress` callback
- [ ] 2.4.3 Verify outline sidebar highlights correctly
- [ ] 2.4.4 Verify progress indicator in status bar

### 2.5 Search in Virtual Context
- [ ] 2.5.1 Create `SearchIndex` struct with block mapping
- [ ] 2.5.2 Pre-compute match-to-block mapping on search
- [x] 2.5.3 Apply highlighting only to visible blocks (LazyVStack handles this)
- [ ] 2.5.4 Verify "next match" scrolls correctly

### 2.6 Phase 2 Verification
- [ ] 2.6.1 Test 50K line doc scrolls at 60fps
- [ ] 2.6.2 Test outline sidebar syncs during scroll
- [ ] 2.6.3 Test progress indicator updates
- [ ] 2.6.4 Test search find/next/previous
- [ ] 2.6.5 Test scrollTo heading from outline
- [ ] 2.6.6 Document Phase 2 metrics

## 3. Phase 3: Virtual Editor Preview (Medium Risk)

### 3.1 Preview Pane Virtualization
- [x] 3.1.1 Apply LazyVStack to edit mode preview pane (uses same MarkdownReaderView)
- [ ] 3.1.2 Share block height cache between reader and preview
- [ ] 3.1.3 Verify preview updates on text change

### 3.2 Visible-Region Editor Highlighting
- [x] 3.2.1 Add `visibleCharacterRange()` helper to NSTextView extension
- [x] 3.2.2 Modify `rehighlight()` to get visible range
- [x] 3.2.3 Apply highlighting only to visible + buffer region (5000 chars each side)
- [x] 3.2.4 Handle scroll revealing unhighlighted text (scroll observation + debounced rehighlight)

### 3.3 Editor-Preview Scroll Sync
- [ ] 3.3.1 Verify scroll sync still works with lazy preview
- [ ] 3.3.2 Handle edit mode toggle scroll restoration

### 3.4 Phase 3 Verification
- [ ] 3.4.1 Test editor responsive on 50K line doc
- [ ] 3.4.2 Test preview updates correctly
- [ ] 3.4.3 Test scroll sync between panes
- [ ] 3.4.4 Test edit mode toggle preserves position
- [ ] 3.4.5 Document Phase 3 metrics

## 4. Phase 4: Polish & Edge Cases

### 4.1 Rapid Scroll Handling
- [x] 4.1.1 Test scrollbar drag behavior
- [x] 4.1.2 Optimize block rendering during fast scroll (chunked virtualization)
- [x] 4.1.3 Disable scroll tracker for very large docs (>5000 blocks)

### 4.2 Block Height Refinement
- [ ] 4.2.1 Tune height estimates based on real content
- [ ] 4.2.2 Add estimates for Mermaid/Math blocks (async render)
- [ ] 4.2.3 Handle dynamic height changes (image load, diagram render)

### 4.3 Memory Optimization
- [ ] 4.3.1 Profile memory on repeated open/close
- [ ] 4.3.2 Verify no leaks in block height cache
- [ ] 4.3.3 Consider cache eviction for very large docs
- [ ] 4.3.4 **HIGH PRIORITY**: 60K doc uses 1GB RAM - investigate AttributedString memory
- [ ] 4.3.5 Consider lazy block parsing (only parse visible chunks)
- [ ] 4.3.6 Consider on-demand chunk rendering (don't keep all chunks in memory)

### 4.4 Testing
- [ ] 4.4.1 Add performance regression tests
- [ ] 4.4.2 Test on oldest supported macOS (14.0)
- [ ] 4.4.3 Test with various content types (code-heavy, table-heavy, image-heavy)

### 4.5 Documentation
- [ ] 4.5.1 Update MEMORY.md with new patterns
- [ ] 4.5.2 Add performance notes to DEVELOPMENT.md
- [ ] 4.5.3 Document final metrics in release notes

## 5. Final Validation

- [ ] 5.1 Full regression test on all document sizes
- [ ] 5.2 Verify all existing features work
- [ ] 5.3 Compare final metrics to Phase 0 baselines
- [ ] 5.4 Sign off on 50K line target met
