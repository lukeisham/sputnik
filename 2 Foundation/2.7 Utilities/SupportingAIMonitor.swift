import Foundation
import Observation

/// The single accountant for all Supporting AI resource-feature API calls.
///
/// **Responsibilities:**
/// - Accumulates token usage across all resource calls (help lookups, completions,
///   More Context) for the current app session.
/// - Writes `SupportingAIUsage` to `AppState.supportingAIUsage` after each call.
/// - Reads the configured model name from `SettingsStore.supportingAIConfig.modelName`.
///
/// **Threading:** `@MainActor` — all `recordUsage` calls happen on the main thread.
/// Resource-feature code calls `recordUsage` after each API response; it never writes
/// to `AppState` directly (SR-1).
///
/// **Lifecycle:** Created at app launch in `SputnikApp`, injected via
/// `.environment(supportingAIMonitor)`. Reset on app launch only (never mid-session).
// @MainActor isolation makes Sendable conformance redundant — the actor enforces
// single-threaded access on the main actor.
@Observable
@MainActor
public final class SupportingAIMonitor {

    // MARK: - Dependencies

    private let settingsStore: SettingsStore
    private let appState: AppState

    // MARK: - Accumulator

    /// Total tokens (input + output) consumed since the last `reset()`.
    private var totalTokensSinceLaunch: Int = 0

    // MARK: - Init

    public init(settingsStore: SettingsStore, appState: AppState) {
        self.settingsStore = settingsStore
        self.appState = appState
    }

    // MARK: - Public API

    /// The configured model name from settings.
    public var modelName: String {
        settingsStore.supportingAIConfig.modelName
    }

    /// Records usage from a Supporting AI API response.
    ///
    /// Call this from any resource feature (modules 3, 4, 8, 9) after a successful
    /// Supporting AI API response. Accumulates the token counts and writes a fresh
    /// `SupportingAIUsage` to `AppState.supportingAIUsage`.
    ///
    /// - Parameters:
    ///   - inputTokens: Tokens used in the request.
    ///   - outputTokens: Tokens used in the response.
    ///   - contextWindow: The context-window capacity of the model used.
    public func recordUsage(inputTokens: Int, outputTokens: Int, contextWindow: Int) {
        totalTokensSinceLaunch += inputTokens + outputTokens
        appState.supportingAIUsage = SupportingAIUsage(
            totalTokensSinceLaunch: totalTokensSinceLaunch,
            contextWindow: contextWindow
        )
    }

    /// Resets the accumulator to zero.
    ///
    /// Called on app launch via `AppDelegate`. Not called mid-session — if the user
    /// changes the Supporting AI model, the counter continues from where it was
    /// (the old tokens were still consumed this session).
    public func reset() {
        totalTokensSinceLaunch = 0
        appState.supportingAIUsage = nil
    }
}
