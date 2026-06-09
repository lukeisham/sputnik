import Foundation

/// Per-session Main AI context-window usage snapshot.
///
/// Mirrors the shape of the removed `ContextUsage` but is explicitly for the
/// Main AI (the user-loaded AI in the terminal). Written by `MainAIMonitor`
/// when Claude Code status-line metrics or other usage data is available.
public struct MainAIContextUsage: Sendable {
    /// Tokens used in the current session.
    public let usedTokens: Int

    /// The context-window token capacity of the detected model.
    public let contextWindow: Int

    /// Percentage of the context window used.
    public var percent: Double {
        guard contextWindow > 0 else { return 0 }
        return Double(usedTokens) / Double(contextWindow) * 100
    }

    public init(usedTokens: Int, contextWindow: Int) {
        self.usedTokens = usedTokens
        self.contextWindow = contextWindow
    }
}

/// Describes an AI model detected in the terminal session.
///
/// Stored as `AppState.mainAIState`; `nil` when no Main AI is active.
/// Written exclusively by `MainAIMonitor`. The Main AI is never configured
/// in Sputnik settings — it is loaded by the user into the terminal.
public struct MainAIState: Sendable {
    /// The detected model name (e.g. "claude-sonnet-4-6", "llama3").
    public let modelName: String

    /// Context-window token count from `ModelCapacity`, if the model is known.
    /// `nil` for unknown models — the status bar shows model name only.
    public let contextWindow: Int?

    /// Per-session usage metrics, if available.
    /// Populated from Claude Code status-line data or other usage sources.
    public let usage: MainAIContextUsage?

    public init(modelName: String, contextWindow: Int?, usage: MainAIContextUsage?) {
        self.modelName = modelName
        self.contextWindow = contextWindow
        self.usage = usage
    }
}
