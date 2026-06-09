import Foundation
import Observation

/// Detects AI models loaded in the terminal session by observing output lines.
///
/// F-8 Terminal Model Detection. Subscribes to a stream of terminal output lines
/// via `pushOutputLine(_:)`, applies pattern-matching rules, and writes the result
/// to `AppState.terminalModelInfo`.
///
/// **Pattern-matching rules:**
/// - Output contains "✻ Welcome to Claude Code" → detected as "claude"; tries
///   to resolve the exact model from `~/.claude/settings.json`.
/// - Input line matches "ollama run <name>" → detected as `<name>`.
/// - Output matches "loaded model: <name>" (ollama server log) → detected as `<name>`.
///
/// When a Claude model is detected, ``ModelCapacity/contextWindow(for:)`` is used
/// to populate the context-window size. Callers should also start
/// ``ClaudeStatusLineReader`` for Claude usage metrics.
///
/// **Threading:** The polling ``Task`` runs at `.background` QoS and uses `[weak self]`
/// to avoid keeping the detector alive after it is no longer referenced (SW-2). All
/// state mutations are `@MainActor`-isolated via the class annotation.
@Observable
@MainActor
public final class TerminalModelDetector {

    // MARK: - Dependencies

    private let appState: AppState

    /// The underlying output stream. Lines are fed via ``pushOutputLine(_:)`` and
    /// consumed by the background polling task.
    private let outputStream: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    // MARK: - Lifecycle state

    private var pollingTask: Task<Void, Never>?

    // MARK: - Init

    /// Creates a detector that writes model-detection results into `appState`.
    ///
    /// - Parameter appState: The shared application state; held strongly for the
    ///   lifetime of the detector.
    public init(appState: AppState) {
        self.appState = appState
        var continuation: AsyncStream<String>.Continuation!
        self.outputStream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    // MARK: - Input

    /// Feeds one line of terminal output into the detector for pattern matching.
    ///
    /// Called by the terminal module (module 7) or any intermediary that bridges
    /// terminal output into Foundation — never stores module 7 internals (SR-1).
    /// This method returns immediately; processing happens asynchronously on the
    /// background polling task.
    ///
    /// - Parameter line: A single line of terminal output, without the trailing newline.
    public func pushOutputLine(_ line: String) {
        continuation.yield(line)
    }

    // MARK: - Lifecycle

    /// Starts the background polling loop that consumes and processes output lines.
    ///
    /// Calling `start()` on an already-running detector is a no-op.
    public func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            for await line in self.outputStream {
                guard !Task.isCancelled else { break }
                await self.processLine(line)
            }
        }
    }

    /// Stops the background polling loop and cancels any pending work.
    ///
    /// After `stop()` the detector can be restarted with a fresh call to `start()`.
    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Pattern matching

    /// Applies the detection rules to a single output line (runs on MainActor).
    private func processLine(_ line: String) {
        if line.contains("\u{2723} Welcome to Claude Code") {
            detectClaude()
        } else if line.hasPrefix("ollama run ") {
            let name = line.dropFirst("ollama run ".count)
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            setModel(name: name)
        } else if line.contains("loaded model: ") {
            let parts = line.components(separatedBy: "loaded model: ")
            guard parts.count >= 2 else { return }
            let name = parts[1].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            setModel(name: name)
        }
    }

    /// Handles the "✻ Welcome to Claude Code" trigger: resolves the exact model
    /// from `~/.claude/settings.json` and writes the detection result.
    private func detectClaude() {
        let resolvedName = resolveClaudeModelFromSettings() ?? "claude"
        let contextWindow = ModelCapacity.contextWindow(for: resolvedName)
        appState.terminalModelInfo = TerminalModelInfo(
            name: resolvedName,
            contextWindow: contextWindow,
            claudeUsage: nil
        )
    }

    /// Reads `~/.claude/settings.json` and extracts the `"model"` field, if present.
    ///
    /// - Returns: The model string from settings, or `nil` if the file cannot be read
    ///   or the key is missing / empty.
    private func resolveClaudeModelFromSettings() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("settings.json")
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let model = json["model"] as? String,
            !model.isEmpty
        else {
            return nil
        }
        return model
    }

    /// Sets the detected model into `appState.terminalModelInfo`, looking up the
    /// context-window size from ``ModelCapacity``.
    private func setModel(name: String) {
        let contextWindow = ModelCapacity.contextWindow(for: name)
        appState.terminalModelInfo = TerminalModelInfo(
            name: name,
            contextWindow: contextWindow,
            claudeUsage: nil
        )
    }

    deinit {
        pollingTask?.cancel()
    }
}
