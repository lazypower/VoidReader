# Capability: Debug Telemetry

Debug logging and telemetry system for diagnosing performance issues during development.

## ADDED Requirements

### Requirement: Environment-Based Activation

The app SHALL enable debug telemetry via environment variables, not compile-time flags.

#### Scenario: Enable debug logging
- **Given** the app is launched with `VOID_READER_DEBUG=1` environment variable
- **When** the app starts
- **Then** debug logging is enabled and logs appear in Console.app

#### Scenario: Disabled by default
- **Given** the app is launched without `VOID_READER_DEBUG` set
- **When** any instrumented code path executes
- **Then** no logging overhead occurs and no logs are produced

#### Scenario: File logging
- **Given** `VOID_READER_DEBUG=1` and `VOID_READER_DEBUG_FILE=/path/to/log.txt` are set
- **When** debug events occur
- **Then** logs are written to the specified file with ISO8601 timestamps

---

### Requirement: Subsystem Filtering

The debug system SHALL categorize logs by subsystem for targeted debugging.

#### Scenario: Filter by subsystem in Console.app
- **Given** debug logging is enabled
- **When** viewing logs in Console.app
- **Then** logs can be filtered by subsystem (rendering, search, scroll, editor, lifecycle, perf)

#### Scenario: Subsystem categories
- **Given** the app is instrumented
- **When** rendering a document
- **Then** render timing logs appear under the `rendering` category
- **And** scroll position logs appear under the `scroll` category

---

### Requirement: Timing Measurements

The debug system SHALL provide timing measurements for instrumented code paths.

#### Scenario: Block rendering timing
- **Given** debug logging is enabled
- **When** `BlockRenderer.render()` completes
- **Then** a log entry shows the render time in milliseconds and document size

#### Scenario: Syntax highlighting timing
- **Given** debug logging is enabled and edit mode is active
- **When** `rehighlight()` completes
- **Then** a log entry shows the highlighting time in milliseconds

#### Scenario: Nested timing
- **Given** debug logging is enabled
- **When** multiple timed operations are nested
- **Then** each operation logs its own timing independently

---

### Requirement: Memory Reporting

The debug system SHALL support logging memory usage at key points.

#### Scenario: Memory at document open
- **Given** debug logging is enabled
- **When** a document is opened
- **Then** current memory usage (in MB) is logged

#### Scenario: Memory on demand
- **Given** debug logging is enabled
- **When** `DebugLog.logMemory()` is called with a context label
- **Then** memory usage is logged with the provided context

---

### Requirement: Zero Overhead When Disabled

Debug logging MUST have no measurable performance impact when disabled.

#### Scenario: No string allocation
- **Given** debug logging is disabled
- **When** a log call with string interpolation is reached
- **Then** the interpolation is not evaluated (via @autoclosure)

#### Scenario: No timing overhead
- **Given** debug logging is disabled
- **When** a `measure()` call wraps a function
- **Then** the wrapper adds negligible overhead (<1 microsecond)
