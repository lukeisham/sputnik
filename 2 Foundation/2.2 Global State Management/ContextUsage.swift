import Foundation

/// Tracks AI context-window usage for the status bar.
/// Populated by any module making AI calls.
public struct ContextUsage: Sendable {
    public let usedTokens: Int
    public let contextWindow: Int

    public var percent: Double {
        guard contextWindow > 0 else { return 0 }
        return Double(usedTokens) / Double(contextWindow) * 100
    }

    public init(usedTokens: Int, contextWindow: Int) {
        self.usedTokens = usedTokens
        self.contextWindow = contextWindow
    }
}
