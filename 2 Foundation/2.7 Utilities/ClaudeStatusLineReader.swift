import Foundation

/// Polls `~/.claude/stats.json` every 5 seconds for Claude Code Status Line data.
///
/// F-8 Terminal Model Detection — Claude usage metrics. Writes the decoded
/// ``ClaudeStatusLineUsage`` into ``AppState/terminalModelInfo``. When the file is
/// absent or the data is older than 30 seconds, the usage is cleared (set to `nil`).
///
/// **Optimisation:** Uses ``DispatchSource/makeFileSystemObjectSource(fileDescriptor:eventMask:queue:)``
/// as a first-alert mechanism so that updated stats are read promptly after a write,
/// before the next polling tick (MR-3: battery-aware scheduling). The 5-second polling
/// interval acts as a safety net so that readings are never stale by more than 5 seconds
/// even if the dispatch-source notification is missed or delayed.
///
/// **Threading:** The polling ``Task`` runs at `.background` QoS and uses `[weak self]`
/// to avoid keeping the reader alive after it is no longer referenced (SW-2). All
/// state mutations are `@MainActor`-isolated via the class annotation.
@MainActor
public final class ClaudeStatusLineReader {

    // MARK: - Dependencies

    private let appState: AppState

    // MARK: - Lifecycle state

    /// Background polling task; `nil` when stopped.
    private var pollingTask: Task<Void, Never>?

    /// File-system watcher on `~/.claude/stats.json` (optimisation: fires promptly on write).
    ///
    /// Uses `DispatchSource.makeFileSystemObjectSource` to observe write/extend/rename/delete
    /// events on the stats file. When triggered, it reads the file immediately rather than
    /// waiting for the next polling tick. The watcher is torn down and recreated on each
    /// `start()` to handle file deletion/recreation (MR-3).
    private var fileWatcher: DispatchSourceFileSystemObject?

    // MARK: - Constants

    /// Interval between polling ticks (seconds).
    private static let pollingInterval: TimeInterval = 5

    /// Maximum age of a stats snapshot before it is considered stale (seconds).
    private static let stalenessThreshold: TimeInterval = 30

    /// The `~/.claude/stats.json` URL.
    private var statsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("stats.json")
    }

    // MARK: - Init

    /// Creates a reader that writes Claude usage data into `appState`.
    ///
    /// - Parameter appState: The shared application state; held strongly for the
    ///   lifetime of the reader.
    public init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Lifecycle

    /// Starts the polling loop and file-watcher.
    ///
    /// If the reader is already running, it is stopped and restarted cleanly
    /// (tearing down any previous file watcher).
    public func start() {
        stop()
        pollingTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.readStatsFile()
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(Self.pollingInterval * 1_000_000_000)
                    )
                } catch {
                    break  // Task was cancelled
                }
            }
        }
        startFileWatcher()
    }

    /// Stops the polling loop and file-watcher.
    ///
    /// After `stop()` the reader can be restarted with a fresh call to `start()`.
    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        stopFileWatcher()
    }

    // MARK: - File reading

    /// Reads and decodes `~/.claude/stats.json`, then updates `appState.terminalModelInfo`.
    ///
    /// - If the file does not exist: clears Claude usage (if a model is currently detected).
    /// - If `capturedAt` is older than ``stalenessThreshold``: treats data as stale and clears usage.
    /// - Otherwise: decodes `five_hour_percent` and `weekly_percent` and writes the result.
    private func readStatsFile() async {
        let url = statsURL

        guard let data = try? Data(contentsOf: url) else {
            // File doesn't exist → clear Claude usage data
            clearClaudeUsage()
            return
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let raw = try decoder.decode(RawStats.self, from: data)
            let now = Date()

            guard now.timeIntervalSince(raw.capturedAt) <= Self.stalenessThreshold else {
                // Stale data — discard
                clearClaudeUsage()
                return
            }

            let usage = ClaudeStatusLineUsage(
                fiveHourPercent: raw.fiveHourPercent,
                weeklyPercent: raw.weeklyPercent,
                capturedAt: raw.capturedAt
            )
            updateClaudeUsage(usage)
        } catch {
            // Malformed or unexpected JSON — clear usage
            clearClaudeUsage()
        }
    }

    /// Sets `claudeUsage` to `nil` on the currently detected model, if any.
    private func clearClaudeUsage() {
        guard let existing = appState.terminalModelInfo else { return }
        appState.terminalModelInfo = TerminalModelInfo(
            name: existing.name,
            contextWindow: existing.contextWindow,
            claudeUsage: nil
        )
    }

    /// Writes a fresh ``ClaudeStatusLineUsage`` into the current model info.
    ///
    /// If no model is currently detected (`terminalModelInfo` is `nil`), the update
    /// is silently ignored — usage data is meaningless without an active model.
    private func updateClaudeUsage(_ usage: ClaudeStatusLineUsage) {
        guard let existing = appState.terminalModelInfo else { return }
        appState.terminalModelInfo = TerminalModelInfo(
            name: existing.name,
            contextWindow: existing.contextWindow,
            claudeUsage: usage
        )
    }

    // MARK: - File watcher (optimisation)

    /// Registers a dispatch-source to watch `~/.claude/stats.json` for writes.
    ///
    /// This is an optimisation over polling alone (MR-3: battery-aware scheduling):
    /// the dispatch source wakes us promptly when the file changes, so the polling
    /// interval can be relaxed to 5 seconds as a safety net rather than a tight loop.
    /// The watcher is recreated on every `start()` call to handle the case where the
    /// file was deleted and recreated (the original descriptor would be invalidated).
    ///
    /// If the `~/.claude/` directory does not exist yet, the watcher is skipped;
    /// the polling loop will pick up the file when it appears.
    private func startFileWatcher() {
        let url = statsURL
        let dir = url.deletingLastPathComponent()

        var isDir: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
            isDir.boolValue
        else {
            return  // directory doesn't exist yet; polling will catch it
        }

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
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

        // Tear down the previous watcher before taking ownership of the new one.
        stopFileWatcher()
        fileWatcher = watcher
    }

    /// Cancels and releases the current file watcher, closing its file descriptor.
    private func stopFileWatcher() {
        fileWatcher?.cancel()
        fileWatcher = nil
    }

    deinit {
        pollingTask?.cancel()
        stopFileWatcher()
    }
}

// MARK: - Raw stats JSON shape

/// Mirrors the structure of `~/.claude/stats.json` for decoding.
///
/// Uses snake_case `CodingKeys` to match the file's JSON keys.
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
