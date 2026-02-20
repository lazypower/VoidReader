import Foundation
import os

/// Debug logging system for diagnosing performance issues.
///
/// Enabled via environment variables:
/// - `VOID_READER_DEBUG=1` - Enable debug logging to Console.app
/// - `VOID_READER_DEBUG_FILE=/path/to/log.txt` - Also write to file
///
/// View logs in Console.app:
/// ```
/// subsystem:com.voidreader.debug category:rendering
/// ```
///
/// Usage:
/// ```swift
/// DebugLog.log(.rendering, "Starting render of \(text.count) chars")
///
/// let result = DebugLog.measure(.rendering, "BlockRenderer.render") {
///     renderer.render(text)
/// }
/// ```
public enum DebugLog {

    // MARK: - Subsystems

    /// Categories for filtering logs in Console.app
    public enum Subsystem: String, CaseIterable {
        case rendering  // BlockRenderer, syntax highlighting
        case search     // TextSearcher, find/replace
        case scroll     // ScrollPositionTracker, block visibility
        case editor     // SyntaxHighlightingEditor, text changes
        case lifecycle  // App launch, document open/close
        case perf       // Memory snapshots, performance baselines

        fileprivate var logger: Logger {
            Logger(subsystem: "com.voidreader.debug", category: rawValue)
        }
    }

    // MARK: - Configuration (evaluated once at launch)

    /// Whether debug logging is enabled (cached from VOID_READER_DEBUG env var)
    public static let isEnabled: Bool = {
        ProcessInfo.processInfo.environment["VOID_READER_DEBUG"] == "1"
    }()

    /// Optional file path for logging (from VOID_READER_DEBUG_FILE env var)
    public static let filePath: String? = {
        ProcessInfo.processInfo.environment["VOID_READER_DEBUG_FILE"]
    }()

    /// File handle for file logging (created once if filePath is set)
    private static let fileHandle: FileHandle? = {
        guard let path = filePath else { return nil }

        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        guard let handle = FileHandle(forWritingAtPath: path) else {
            print("[DebugLog] Failed to open file for writing: \(path)")
            return nil
        }

        // Seek to end for appending
        try? handle.seekToEnd()

        // Write header
        let header = "=== VoidReader Debug Log Started: \(ISO8601DateFormatter().string(from: Date())) ===\n"
        handle.write(Data(header.utf8))

        return handle
    }()

    /// ISO8601 formatter for file logging
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: - Logging Methods

    /// Log a debug message (os_log level: debug)
    public static func log(_ subsystem: Subsystem, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let msg = message()
        subsystem.logger.debug("\(msg, privacy: .public)")
        writeToFile(subsystem: subsystem, level: "DEBUG", message: msg)
    }

    /// Log an info message (os_log level: info)
    public static func info(_ subsystem: Subsystem, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let msg = message()
        subsystem.logger.info("\(msg, privacy: .public)")
        writeToFile(subsystem: subsystem, level: "INFO", message: msg)
    }

    /// Log a warning message (os_log level: default)
    public static func warning(_ subsystem: Subsystem, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let msg = message()
        subsystem.logger.warning("\(msg, privacy: .public)")
        writeToFile(subsystem: subsystem, level: "WARN", message: msg)
    }

    /// Log an error message (os_log level: error)
    /// Note: Error logs are always written, even when debug is disabled
    public static func error(_ subsystem: Subsystem, _ message: @autoclosure () -> String) {
        let msg = message()
        subsystem.logger.error("\(msg, privacy: .public)")
        if isEnabled {
            writeToFile(subsystem: subsystem, level: "ERROR", message: msg)
        }
    }

    // MARK: - File Logging

    private static func writeToFile(subsystem: Subsystem, level: String, message: String) {
        guard let handle = fileHandle else { return }
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] [\(subsystem.rawValue)] \(message)\n"
        handle.write(Data(line.utf8))
    }

    // MARK: - Timing

    /// Token returned by startTiming, passed to endTiming
    public struct TimingToken {
        public let subsystem: Subsystem
        public let label: String
        public let start: CFAbsoluteTime

        fileprivate init(subsystem: Subsystem, label: String) {
            self.subsystem = subsystem
            self.label = label
            self.start = CFAbsoluteTimeGetCurrent()
        }
    }

    /// Start timing an operation. Returns nil if logging is disabled.
    public static func startTiming(_ subsystem: Subsystem, _ label: String) -> TimingToken? {
        guard isEnabled else { return nil }
        return TimingToken(subsystem: subsystem, label: label)
    }

    /// End timing an operation and log the duration.
    public static func endTiming(_ token: TimingToken?) {
        guard let token = token else { return }
        let elapsed = CFAbsoluteTimeGetCurrent() - token.start
        let ms = elapsed * 1000
        log(token.subsystem, "\(token.label): \(String(format: "%.2f", ms))ms")
    }

    /// Measure and log the duration of a synchronous block.
    public static func measure<T>(
        _ subsystem: Subsystem,
        _ label: String,
        _ block: () throws -> T
    ) rethrows -> T {
        guard isEnabled else { return try block() }
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let ms = elapsed * 1000
        log(subsystem, "\(label): \(String(format: "%.2f", ms))ms")
        return result
    }

    /// Measure and log the duration of an async block.
    public static func measureAsync<T>(
        _ subsystem: Subsystem,
        _ label: String,
        _ block: () async throws -> T
    ) async rethrows -> T {
        guard isEnabled else { return try await block() }
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let ms = elapsed * 1000
        log(subsystem, "\(label): \(String(format: "%.2f", ms))ms")
        return result
    }

    // MARK: - Memory Reporting

    /// Log current memory usage with a context label.
    public static func logMemory(_ subsystem: Subsystem, context: String) {
        guard isEnabled else { return }

        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let mb = Double(info.resident_size) / 1_048_576.0
            log(subsystem, "\(context): \(String(format: "%.1f", mb)) MB")
        } else {
            log(subsystem, "\(context): memory unavailable")
        }
    }

    // MARK: - Convenience

    /// Log document metrics (commonly used after rendering)
    public static func documentMetrics(
        charCount: Int,
        blockCount: Int,
        renderTimeMs: Double
    ) {
        guard isEnabled else { return }
        log(.perf, "Document: \(charCount) chars, \(blockCount) blocks, rendered in \(String(format: "%.2f", renderTimeMs))ms")
    }

    /// Log app startup info
    public static func logStartup() {
        guard isEnabled else { return }
        info(.lifecycle, "VoidReader debug logging enabled")
        if let path = filePath {
            info(.lifecycle, "File logging to: \(path)")
        }
        logMemory(.lifecycle, context: "Startup memory")
    }
}
