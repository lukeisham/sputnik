import Foundation

/// Cumulative Supporting AI token usage for the current app session.
///
/// Reset to zero on app launch. Accumulated across all resource-feature calls
/// (help lookups, completions, More Context). Displayed in the Supporting AI
/// settings tab as a session statistic — not persisted.
public struct SupportingAIUsage: Sendable {
    /// Total tokens consumed (input + output) since the app launched.
    public let totalTokensSinceLaunch: Int

    /// The context-window token capacity of the configured model.
    public let contextWindow: Int

    /// Percentage of the context window used, capped at 100.
    public var percentUsed: Double {
        guard contextWindow > 0 else { return 0 }
        return min(Double(totalTokensSinceLaunch) / Double(contextWindow) * 100, 100)
    }

    public init(totalTokensSinceLaunch: Int, contextWindow: Int) {
        self.totalTokensSinceLaunch = totalTokensSinceLaunch
        self.contextWindow = contextWindow
    }
}
