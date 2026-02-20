# Tasks: Debug Telemetry

## 1. Core Infrastructure

- [x] 1.1 Create `Sources/VoidReaderCore/Utilities/DebugLog.swift` with:
  - [x] 1.1.1 `Subsystem` enum (rendering, search, scroll, editor, lifecycle, perf)
  - [x] 1.1.2 `isEnabled` static property (cached from `VOID_READER_DEBUG` env var)
  - [x] 1.1.3 `filePath` static property (from `VOID_READER_DEBUG_FILE` env var)
  - [x] 1.1.4 Per-subsystem `os.Logger` instances
  - [x] 1.1.5 `log()`, `info()`, `warning()`, `error()` methods with @autoclosure
  - [x] 1.1.6 `TimingToken` struct
  - [x] 1.1.7 `startTiming()` / `endTiming()` methods
  - [x] 1.1.8 `measure()` sync wrapper
  - [x] 1.1.9 `measureAsync()` async wrapper
  - [x] 1.1.10 `logMemory()` using mach_task_basic_info
  - [x] 1.1.11 Optional file logging with ISO8601 timestamps

- [x] 1.2 Export from VoidReaderCore module
  - [x] 1.2.1 Add `DebugLog` to public exports in VoidReaderCore.swift

- [x] 1.3 Verify basic functionality
  - [x] 1.3.1 Build succeeds
  - [x] 1.3.2 Test with VOID_READER_DEBUG=1, logs appear in Console.app
  - [x] 1.3.3 Test without env var, no logs appear

## 2. High-Priority Instrumentation (Freeze Investigation)

- [x] 2.1 BlockRenderer instrumentation
  - [x] 2.1.1 Wrap `render()` in `DebugLog.measure(.rendering, ...)`
  - [x] 2.1.2 Log text length and resulting block count

- [x] 2.2 ContentView instrumentation
  - [x] 2.2.1 Log document open in `onAppear` (filename, size)
  - [x] 2.2.2 Log sync vs async path in `updateRenderedBlocks()`
  - [x] 2.2.3 Log render timing for sync path
  - [ ] 2.2.4 Log debounce subscription setup

- [x] 2.3 SyntaxHighlightingEditor instrumentation
  - [x] 2.3.1 Wrap `rehighlight()` in timing measurement
  - [ ] 2.3.2 Log debounce timer events (throttled)

- [ ] 2.4 MarkdownReaderView instrumentation
  - [ ] 2.4.1 Log scroll position updates (debounced)
  - [ ] 2.4.2 Log chunk transitions for large docs

## 3. Additional Instrumentation

- [ ] 3.1 TextSearcher instrumentation
  - [ ] 3.1.1 Log search query, text size, match count
  - [ ] 3.1.2 Log search timing

- [x] 3.2 App lifecycle instrumentation
  - [x] 3.2.1 Log app launch in VoidReaderApp.init
  - [x] 3.2.2 Log initial memory usage
  - [ ] 3.2.3 Log document close

## 4. Developer Experience

- [x] 4.1 Add `make run-debug` target to Makefile
  - [x] 4.1.1 Sets VOID_READER_DEBUG=1 and runs app

- [ ] 4.2 Update DEVELOPMENT.md
  - [ ] 4.2.1 Document debug telemetry usage
  - [ ] 4.2.2 Document Console.app filtering

## 5. Verification

- [ ] 5.1 Open 50K line test document with debug enabled
  - [ ] 5.1.1 Verify render timing appears in logs
  - [ ] 5.1.2 Verify scroll events appear
  - [ ] 5.1.3 Verify memory logged at milestones

- [ ] 5.2 Run without debug flag
  - [ ] 5.2.1 Verify no visible logs
  - [ ] 5.2.2 Profile with Instruments - no overhead

- [x] 5.3 Test file logging
  - [x] 5.3.1 Set VOID_READER_DEBUG_FILE, verify file created
  - [x] 5.3.2 Verify timestamps and formatting

## 6. XCUITest Infrastructure (Added)

- [x] 6.1 Add XCUITest target to project.yml
- [x] 6.2 Create VoidReaderUITestCase base class
- [x] 6.3 Create LargeDocumentTests suite
- [x] 6.4 Add accessibility identifiers to key views
- [x] 6.5 Add `make test-ui` target to Makefile
- [x] 6.6 Add --open argument handling to VoidReaderApp
