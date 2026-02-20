# Proposal: Add Debug Telemetry

## Summary

Add a debug logging/telemetry system using Apple's unified logging (`os.Logger`) to help diagnose performance issues like UI freezes. Enabled via environment variable, zero overhead when disabled.

## Motivation

The `optimize-large-document-performance` work requires baseline measurements (scroll FPS, keystroke latency, memory usage) but there's no instrumentation infrastructure. When freezes occur, there's no visibility into which subsystem is responsible (rendering? layout? main thread congestion?).

Current state:
- Scattered `print()` statements for errors only
- No timing measurements anywhere
- No structured logging or subsystem filtering
- No way to enable diagnostics without code changes

## Scope

**In scope:**
- Debug logging utility in VoidReaderCore
- Environment variable activation (`VOID_READER_DEBUG=1`)
- Subsystem-based filtering (rendering, search, scroll, editor, lifecycle, perf)
- Timing measurement helpers (sync and async)
- Memory usage logging
- Optional file output (`VOID_READER_DEBUG_FILE=/path`)
- Instrumentation of key performance-sensitive code paths
- `make run-debug` convenience target

**Out of scope:**
- Production analytics or crash reporting
- User-facing logging preferences
- Remote telemetry or data collection
- Automatic performance regression detection

## Approach

Use Apple's `os.Logger` for:
- Native Console.app integration with subsystem/category filtering
- Zero overhead when logs are not being collected
- Proper privacy controls (`.public` for debug data)

Wrap in a `DebugLog` utility that:
- Caches `isEnabled` at launch from environment variable
- Uses `@autoclosure` to prevent string allocation when disabled
- Provides `measure()` helpers for timing blocks
- Follows existing VoidReaderCore utility patterns

## Success Criteria

1. Running with `VOID_READER_DEBUG=1` shows logs in Console.app
2. Logs can be filtered by subsystem (e.g., `com.voidreader.debug:rendering`)
3. Opening a 50K line document shows render timing in logs
4. Running WITHOUT the env var shows no performance degradation
5. File logging works when `VOID_READER_DEBUG_FILE` is set

## Related Changes

- `optimize-large-document-performance` - will use telemetry for baseline measurements (tasks 0.2-0.5)

## Risks

- **Low**: Adding `import os` increases binary slightly (negligible)
- **Low**: Instrumentation points could become stale as code evolves
