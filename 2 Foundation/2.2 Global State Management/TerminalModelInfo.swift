import Foundation

/// Describes an AI model detected in the terminal session.
///
/// Stored as `AppState.terminalModelInfo`; `nil` when no model is active.
public struct TerminalModelInfo: Sendable {
    /// The detected model name (e.g. `"claude-opus-4-8"`, `"llama3"`).
    public let name: String

    /// Context-window token count from `ModelCapacity`, if the model is known.
    public let contextWindow: Int?

    /// Claude Code Status Line metrics, if the detected model is a Claude model
    /// and the status data file has been loaded within the last 30 seconds.
    public let claudeUsage: ClaudeStatusLineUsage?

    public init(name: String, contextWindow: Int?, claudeUsage: ClaudeStatusLineUsage?) {
        self.name = name
        self.contextWindow = contextWindow
        self.claudeUsage = claudeUsage
    }
}

/// Claude Code Status Line token-usage snapshot.
///
/// Both percentages are 0–100. `capturedAt` is used to detect staleness
/// (values older than 30 seconds are discarded).
public struct ClaudeStatusLineUsage: Sendable {
    /// Token usage percentage over the 5-hour rolling window.
    public let fiveHourPercent: Double

    /// Token usage percentage over the current billing week.
    public let weeklyPercent: Double

    /// When this snapshot was captured. If more than 30 seconds old, the
    /// data is considered stale and not displayed.
    public let capturedAt: Date

    public init(fiveHourPercent: Double, weeklyPercent: Double, capturedAt: Date) {
        self.fiveHourPercent = fiveHourPercent
        self.weeklyPercent = weeklyPercent
        self.capturedAt = capturedAt
    }
}
