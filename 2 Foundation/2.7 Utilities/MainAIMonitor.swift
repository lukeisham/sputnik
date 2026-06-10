import Foundation
import Observation

// MARK: - Protocol

/// Terminal module calls this when a new output line arrives, so Foundation can
/// detect AI sessions without Terminal importing Foundation's monitor directly.
///
/// Owned by Foundation (2.7). Terminal depends only on this protocol (SR-1).
public protocol TerminalAIOutputObserving: AnyObject {
    /// Called by `TerminalSession` for each decoded line of terminal output.
    /// - Parameter line: A single line of terminal output, without the trailing newline.
    func observe(line: String)
}

// MARK: - MainAIMonitor

/// Monitors terminal output to detect and track the Main AI session.
///
/// **Main AI** is any AI the user loads into the terminal — Claude Code CLI,
/// an Ollama model, Gemini CLI, or any other AI tool. Sputnik does not configure,
/// launch, or control the Main AI; it only monitors and displays its state.
///
/// **Detection rules:**
/// - Output contains "✻ Welcome to Claude Code" → detects as Claude model;
///   resolves exact model name from `~/.claude/settings.json`.
/// - Output matches "ollama run <name>" → detects as `<name>`.
/// - Output matches "loaded model: <name>" (Ollama server log) → detects as `<name>`.
///
/// When a Claude model is detected, ``ModelCapacity/contextWindow(for:)`` is used
/// to populate the context-window size. ``ClaudeStatusLineReader``-style polling of
/// `~/.claude/stats.json` is handled internally for Claude usage metrics.
///
/// **Threading:** `@MainActor` — all state mutations happen on the main thread.
/// Line observation is thread-safe (fed into an `AsyncStream` processed on
/// `@MainActor`).
///
/// **Lifecycle:** Created at app launch in `SputnikApp` and registered as the
/// `aiOutputObserver` on `TerminalSession`. Also injected into the environment so
/// the StatusBarView can call `setManual(modelName:)`.
@Observable
@MainActor
public final class MainAIMonitor {

    // MARK: - Dependencies

    private let appState: AppState

    // MARK: - Internal stream for line processing

    /// Lines are fed via `observe(line:)` and processed asynchronously.
    private let lineStream: AsyncStream<String>
    private let lineContinuation: AsyncStream<String>.Continuation

    /// Background task that processes incoming lines.
    private var processingTask: Task<Void, Never>?

    // MARK: - Claude stats polling

    /// Background polling task for `~/.claude/stats.json` (Claude usage metrics).
    private var statsPollingTask: Task<Void, Never>?

    /// File-system watcher on `~/.claude/stats.json`.
    private var fileWatcher: DispatchSourceFileSystemObject?

    // MARK: - Constants

    private static let pollingInterval: TimeInterval = 5
    private static let stalenessThreshold: TimeInterval = 30

    private var statsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("stats.json")
    }

    // MARK: - Init

    public init(appState: AppState) {
        self.appState = appState
        var cont: AsyncStream<String>.Continuation!
        self.lineStream = AsyncStream { cont = $0 }
        self.lineContinuation = cont
        startProcessing()
    }

    deinit {
        processingTask?.cancel()
        statsPollingTask?.cancel()
        fileWatcher?.cancel()
    }

    // MARK: - Public API

    /// Records a usage update for the currently detected Main AI.
    ///
    /// Called when Claude Code status-line metrics are received or any other
    /// usage-data source provides token counts.
    ///
    /// - Parameters:
    ///   - usedTokens: Tokens consumed in the current session.
    ///   - contextWindow: The context-window capacity of the model.
    public func updateUsage(usedTokens: Int, contextWindow: Int) {
        guard let currentState = appState.mainAIState else { return }
        let usage = MainAIContextUsage(usedTokens: usedTokens, contextWindow: contextWindow)
        appState.mainAIState = MainAIState(
            modelName: currentState.modelName,
            contextWindow: contextWindow,
            usage: usage
        )
    }

    /// Manually declares a Main AI model by name.
    ///
    /// Allows the user to set the model name when the AI CLI does not emit
    /// a detectable signature. `contextWindow` is looked up from ``ModelCapacity``.
    ///
    /// - Parameter modelName: The model name to display (e.g. "my-custom-model").
    public func setManual(modelName: String) {
        let contextWindow = ModelCapacity.contextWindow(for: modelName)
        appState.mainAIState = MainAIState(
            modelName: modelName,
            contextWindow: contextWindow,
            usage: nil
        )
    }

    /// Clears the current Main AI detection.
    public func clear() {
        appState.mainAIState = nil
    }

    // MARK: - Line processing

    private func startProcessing() {
        processingTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            for await line in self.lineStream {
                guard !Task.isCancelled else { break }
                self.processLine(line)
            }
        }
    }

    private func processLine(_ line: String) {
        if line.contains("\u{2723} Welcome to Claude Code") {
            detectClaude()
        } else if line.hasPrefix("ollama run ") {
            let name = line.dropFirst("ollama run ".count)
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            setDetected(modelName: String(name))
        } else if line.contains("loaded model: ") {
            let parts = line.components(separatedBy: "loaded model: ")
            guard parts.count >= 2 else { return }
            let name = parts[1].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            setDetected(modelName: name)
        } else if line == "clear" || line == "exit" {
            // Terminal session boundary — clear the detected model when the shell resets.
            clear()
        }
    }

    // MARK: - Claude detection

    private func detectClaude() {
        let resolvedName = resolveClaudeModelFromSettings() ?? "claude"
        let contextWindow = ModelCapacity.contextWindow(for: resolvedName)
        appState.mainAIState = MainAIState(
            modelName: resolvedName,
            contextWindow: contextWindow,
            usage: nil
        )
        // Start polling Claude stats for usage metrics.
        startStatsPolling()
    }

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

    private func setDetected(modelName: String) {
        let contextWindow = ModelCapacity.contextWindow(for: modelName)
        appState.mainAIState = MainAIState(
            modelName: modelName,
            contextWindow: contextWindow,
            usage: nil
        )
    }
}

// MARK: - TerminalAIOutputObserving

extension MainAIMonitor: TerminalAIOutputObserving {
    public nonisolated func observe(line: String) {
        lineContinuation.yield(line)
    }
}

// MARK: - Claude stats polling (migrated from ClaudeStatusLineReader)

extension MainAIMonitor {

    private func startStatsPolling() {
        stopStatsPolling()
        statsPollingTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.readStatsFile()
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(Self.pollingInterval * 1_000_000_000)
                    )
                } catch {
                    break
                }
            }
        }
        startFileWatcher()
    }

    private func stopStatsPolling() {
        statsPollingTask?.cancel()
        statsPollingTask = nil
        stopFileWatcher()
    }

    private func readStatsFile() async {
        let url = statsURL

        guard let data = try? Data(contentsOf: url) else {
            clearClaudeUsage()
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let raw = try decoder.decode(RawStats.self, from: data)
            let now = Date()

            guard now.timeIntervalSince(raw.capturedAt) <= Self.stalenessThreshold else {
                clearClaudeUsage()
                return
            }

            // Derive usedTokens from the five-hour percent and context window.
            if let state = appState.mainAIState, let contextWindow = state.contextWindow {
                let usedTokens = Int(Double(contextWindow) * (raw.fiveHourPercent / 100.0))
                let usage = MainAIContextUsage(usedTokens: usedTokens, contextWindow: contextWindow)
                appState.mainAIState = MainAIState(
                    modelName: state.modelName,
                    contextWindow: contextWindow,
                    usage: usage
                )
            }
        } catch {
            clearClaudeUsage()
        }
    }

    private func clearClaudeUsage() {
        guard let existing = appState.mainAIState else { return }
        appState.mainAIState = MainAIState(
            modelName: existing.modelName,
            contextWindow: existing.contextWindow,
            usage: nil
        )
    }

    // MARK: - File watcher

    private func startFileWatcher() {
        let url = statsURL
        let dir = url.deletingLastPathComponent()

        var isDir: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
            isDir.boolValue
        else {
            return
        }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            // MR-3: DispatchQueue.global is necessary here because DispatchSource
            // has no async/await equivalent; the QoS is .background to minimise
            // battery impact.
            queue: DispatchQueue.global(qos: .background)
        )

        watcher.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.readStatsFile()
            }
        }

        watcher.setCancelHandler {
            close(fd)
        }

        watcher.resume()
        stopFileWatcher()
        fileWatcher = watcher
    }

    private func stopFileWatcher() {
        fileWatcher?.cancel()
        fileWatcher = nil
    }
}

// MARK: - Raw stats JSON shape

private struct RawStats: Decodable {
    let fiveHourPercent: Double
    let weeklyPercent: Double
    let capturedAt: Date

    enum CodingKeys: String, CodingKey {
        case fiveHourPercent = "five_hour_percent"
        case weeklyPercent = "weekly_percent"
        case capturedAt = "captured_at"
    }
}
