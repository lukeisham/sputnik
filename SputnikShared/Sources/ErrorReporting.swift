import Foundation
import os.log

/// A centralized error reporting actor for non-fatal errors across all modules.
///
/// Writes to both `os_log` (for debugging) and an in-memory ring buffer
/// (for future telemetry). Uses an actor to ensure thread-safe logging from any context.
///
/// Usage:
/// ```swift
/// await ErrorReporting.shared.log("Some warning", category: "TextEditor")
/// await ErrorReporting.shared.report(error, category: "HTMLPreview")
/// ```
// Actor isolation provides Sendable safety automatically; @unchecked is not needed.
public actor ErrorReporting {

    /// Shared singleton instance.
    public static let shared = ErrorReporting()

    // MARK: - In-memory ring buffer

    private var ringBuffer: [LogEntry] = []
    private let maxEntries = 1000

    private struct LogEntry: Sendable {
        let timestamp: Date
        let level: Level
        let message: String
        let category: String

        enum Level: String, Sendable {
            case debug = "DEBUG"
            case info = "INFO"
            case warning = "WARNING"
            case error = "ERROR"
        }
    }

    // MARK: - Public API

    /// Logs a non-fatal error to both os_log and the ring buffer.
    ///
    /// - Parameters:
    ///   - message: Human-readable error description.
    ///   - category: Module or subsystem (e.g. "Markdown Preview", "Terminal").
    ///   - file: Source file (auto-captured).
    ///   - line: Source line (auto-captured).
    public func log(
        _ message: String,
        category: String = "Default",
        file: String = #file,
        line: Int = #line
    ) {
        let entry = LogEntry(
            timestamp: Date(),
            level: .warning,
            message: message,
            category: category
        )
        addToRingBuffer(entry)

        let osLog = OSLog(subsystem: "app.sputnik.\(category)", category: "warning")
        os_log(
            "%{public}@:%d %{public}@", log: osLog, type: .default,
            (file as NSString).lastPathComponent, line, message)
    }

    /// Reports an error to both os_log and the ring buffer.
    ///
    /// - Parameters:
    ///   - error: The error value (will be formatted as `"\(error)"`).
    ///   - category: Module or subsystem.
    ///   - file: Source file (auto-captured).
    ///   - line: Source line (auto-captured).
    public func report(
        _ error: Error,
        category: String = "Default",
        file: String = #file,
        line: Int = #line
    ) {
        let message = "\(error)"
        let entry = LogEntry(
            timestamp: Date(),
            level: .error,
            message: message,
            category: category
        )
        addToRingBuffer(entry)

        let osLog = OSLog(subsystem: "app.sputnik.\(category)", category: "error")
        os_log(
            "%{public}@:%d %{public}@", log: osLog, type: .error,
            (file as NSString).lastPathComponent, line, message)
    }

    /// Returns a copy of recent log entries (for debugging/telemetry).
    public func recentEntries(limit: Int = 50) -> [String] {
        let entries = ringBuffer.suffix(limit)
        return entries.map { entry in
            let formatter = ISO8601DateFormatter()
            let time = formatter.string(from: entry.timestamp)
            return "[\(time)] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
        }
    }

    // MARK: - Private helpers

    private func addToRingBuffer(_ entry: LogEntry) {
        ringBuffer.append(entry)
        if ringBuffer.count > maxEntries {
            ringBuffer.removeFirst()
        }
    }
}
