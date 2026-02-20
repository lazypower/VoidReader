# Design: Debug Telemetry System

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        App Layer                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ ContentView │  │ ReaderView  │  │ SyntaxHighlighting  │  │
│  │             │  │             │  │      Editor         │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
│         │                │                     │             │
│         └────────────────┼─────────────────────┘             │
│                          │ DebugLog.log/measure              │
│                          ▼                                   │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                    VoidReaderCore                      │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │              DebugLog (Utilities/)              │  │  │
│  │  │  • isEnabled (cached from env var)              │  │  │
│  │  │  • Subsystem enum (rendering, search, etc.)     │  │  │
│  │  │  • log(), info(), warning(), error()            │  │  │
│  │  │  • startTiming/endTiming/measure                │  │  │
│  │  │  • logMemory()                                  │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                          │                             │  │
│  │  ┌───────────┐  ┌───────┴───────┐  ┌───────────────┐  │  │
│  │  │ Renderer  │  │ TextSearcher  │  │ Other Utils   │  │  │
│  │  └───────────┘  └───────────────┘  └───────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
            ┌─────────────────────────┐
            │      os.Logger          │
            │  subsystem: com.void... │
            │  category: per-subsys   │
            └───────────┬─────────────┘
                        │
          ┌─────────────┼─────────────┐
          ▼             ▼             ▼
    Console.app    File (opt)    Instruments
```

## Subsystems

| Subsystem | Category String | Instrumentation Points |
|-----------|-----------------|------------------------|
| `.rendering` | `rendering` | BlockRenderer.render(), syntax highlighting |
| `.search` | `search` | TextSearcher.findMatches(), search index building |
| `.scroll` | `scroll` | ScrollPositionTracker, block visibility |
| `.editor` | `editor` | textDidChange, rehighlight, debounce events |
| `.lifecycle` | `lifecycle` | App launch, document open/close, file watcher |
| `.perf` | `perf` | Memory snapshots, document metrics, milestones |

## API Design

```swift
public enum DebugLog {
    // Configuration (evaluated once at launch)
    public static let isEnabled: Bool
    public static let filePath: String?

    // Logging
    public static func log(_ subsystem: Subsystem, _ message: @autoclosure () -> String)
    public static func info(_ subsystem: Subsystem, _ message: @autoclosure () -> String)
    public static func warning(_ subsystem: Subsystem, _ message: @autoclosure () -> String)
    public static func error(_ subsystem: Subsystem, _ message: @autoclosure () -> String)

    // Timing
    public static func startTiming(_ subsystem: Subsystem, _ label: String) -> TimingToken?
    public static func endTiming(_ token: TimingToken?)
    public static func measure<T>(_ subsystem: Subsystem, _ label: String, _ block: () throws -> T) rethrows -> T
    public static func measureAsync<T>(_ subsystem: Subsystem, _ label: String, _ block: () async throws -> T) async rethrows -> T

    // Performance
    public static func logMemory(_ subsystem: Subsystem, context: String)
    public static func documentMetrics(charCount: Int, blockCount: Int, renderTimeMs: Double)
}

public struct TimingToken {
    let subsystem: DebugLog.Subsystem
    let label: String
    let start: CFAbsoluteTime
}
```

## Zero-Overhead Design

1. **Cached enable flag**: `isEnabled` is evaluated once from `ProcessInfo.processInfo.environment` at static initialization
2. **Early guard**: All methods guard on `isEnabled` first
3. **@autoclosure messages**: String interpolation only happens if logging is enabled
4. **@inlinable**: Allows compiler to inline and eliminate dead code paths
5. **Optional TimingToken**: Returns `nil` when disabled, no allocation

```swift
@inlinable
public static func log(_ subsystem: Subsystem, _ message: @autoclosure () -> String) {
    guard isEnabled else { return }  // No work when disabled
    let msg = message()  // String only evaluated here
    subsystem.logger.debug("\(msg, privacy: .public)")
}
```

## File Logging

Optional, enabled via `VOID_READER_DEBUG_FILE=/path/to/log.txt`:
- Creates file at launch if path is set
- Appends ISO8601 timestamped lines
- Useful for post-mortem analysis or sharing logs

## Instrumentation Strategy

### High Priority (freeze investigation)

1. **BlockRenderer.render()** - Main rendering path
   ```swift
   return DebugLog.measure(.rendering, "BlockRenderer.render(\(text.count) chars)") {
       // existing implementation
   }
   ```

2. **ContentView.updateRenderedBlocks()** - Sync vs async path
   ```swift
   DebugLog.log(.rendering, "updateRenderedBlocks: \(text.count < 50_000 ? "sync" : "async")")
   ```

3. **SyntaxHighlightingEditor.rehighlight()** - Editor highlighting
   ```swift
   DebugLog.measure(.editor, "rehighlight") { ... }
   ```

### Medium Priority

4. **ScrollPositionTracker** - Scroll events
5. **TextSearcher** - Search performance
6. **App lifecycle** - Document open/close timing

## Console.app Usage

Filter by subsystem:
```
subsystem:com.voidreader.debug
```

Filter by category:
```
subsystem:com.voidreader.debug category:rendering
```

## Trade-offs

| Decision | Alternative | Rationale |
|----------|-------------|-----------|
| `os.Logger` | Custom file logger | Native integration, better performance, Console.app support |
| Environment variable | Launch argument | Works with `open -a`, easier for Makefile targets |
| Single DebugLog enum | Per-subsystem loggers | Simpler API, centralized configuration |
| @autoclosure messages | Explicit closures | Cleaner call sites, familiar Swift pattern |
