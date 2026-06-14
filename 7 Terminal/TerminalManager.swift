import Foundation
import FoundationModule
import SwiftUI

/// Coordinates the `TerminalSession` and `TerminalEmulator` for the terminal panel.
///
/// Runs on `@MainActor` so it can observe `AppState.activeWorkspaceDirectory`
/// and update SwiftUI state without actor hops. Conforms to `TerminalLifecycle`
/// (2.6) so `AppDelegate` can cleanly terminate all PTY sessions on quit without
/// importing the Terminal module directly (SR-1).
///
/// The manager is the sole writer for all terminal UI state; `TerminalView` reads
/// from it via `@StateObject` / `@ObservedObject`.
@MainActor
public final class TerminalManager: ObservableObject, TerminalLifecycle, TerminalCommanding {

    /// Stable identity for tab management within a window.
    public let id = UUID()

    // MARK: - Published UI state

    /// The latest grid snapshot to render. `nil` until the session starts.
    @Published public private(set) var snapshot: EmulatorSnapshot?

    /// Non-nil when the session has failed and a diagnostic should be shown.
    @Published public private(set) var pendingAlert: SputnikAlert?

    /// Whether the session is currently running.
    @Published public private(set) var isRunning: Bool = false

    // MARK: - AI output observer

    /// Weak reference to the Main AI output observer (Foundation 2.7).
    /// Set by `TerminalView` from the environment; handed to each new
    /// `TerminalSession` at `start()` so Foundation can detect AI sessions without
    /// Terminal importing the monitor directly (SR-1). MainActor-isolated — both the
    /// `TerminalView` setter and the `startSession` read run on the main actor.
    public weak var aiOutputObserver: TerminalAIOutputObserving?

    /// Weak reference to the TerminalTextView for selection queries.
    /// Set by `TerminalView` via `TerminalRenderer.onTextViewCreated`.
    public nonisolated(unsafe) weak var terminalTextView: TerminalTextView?

    private var session: TerminalSession?
    private var emulator: TerminalEmulator?
    private var pumpTask: Task<Void, Never>?
    private var currentWorkingDirectory: URL?

    // MARK: - Last known grid size (seeded at session start, updated on resize)

    private var lastCols: UInt16 = 80
    private var lastRows: UInt16 = 24

    // MARK: - Resize coalescing (ISS-078)

    /// The single in-flight resize loop, if any. A burst of `resize` calls during a
    /// live drag updates `lastCols`/`lastRows` and sets `resizePending`; the running
    /// loop always re-reads the *latest* dimensions, so the final applied size matches
    /// the last resize even though each apply has async `await` suspension points.
    private var resizeLoop: Task<Void, Never>?
    private var resizePending = false

    // MARK: - Init / deinit

    public init() {}

    deinit {
        pumpTask?.cancel()
        resizeLoop?.cancel()
    }

    // MARK: - Session lifecycle

    /// Starts a new Zsh session rooted at `directory` using the supplied terminal `profile`.
    ///
    /// Cleans up any previous session first. On PTY or launch failure, sets
    /// `pendingAlert` for `TerminalView` to present via `SputnikAlert`.
    public func startSession(directory: URL? = nil, profile: TerminalProfile = .default) async {
        await stopSession()

        let sess = TerminalSession()
        let emu = TerminalEmulator(
            cols: 80, rows: 24,
            profile: profile
        )
        self.session = sess
        self.emulator = emu

        do {
            try await sess.start(workingDirectory: directory, observer: aiOutputObserver)
        } catch let err as SputnikError {
            pendingAlert = SputnikAlert.custom(
                title: "Terminal Error",
                message: err.localizedDescription
            )
            return
        } catch {
            pendingAlert = SputnikAlert.custom(
                title: "Terminal Error",
                message: error.localizedDescription
            )
            return
        }

        isRunning = true
        currentWorkingDirectory = directory

        // Seed the real grid size now that the session is alive (step 5).
        // This overrides the transient 80×24 used for initial emulator construction.
        if lastCols != 80 || lastRows != 24 {
            await emu.resize(cols: Int(lastCols), rows: Int(lastRows))
        }
        await sess.resize(cols: lastCols, rows: lastRows)
        self.snapshot = await emu.snapshot()

        // Pump the session's AsyncStream into the emulator and refresh snapshots.
        // This Task inherits @MainActor isolation from startSession — MainActor.run is a no-op here (ISS-084).
        // `self` is re-resolved weakly each iteration so the pump never holds the
        // manager alive for the loop's lifetime; `deinit { pumpTask?.cancel() }` can
        // then fire mid-run (ISS-069). `sess`/`emu` are captured strongly on purpose
        // — they must outlive the pump that drains them.
        pumpTask = Task { [weak self] in
            for await data in sess.outputStream {
                guard let self else { break }
                await emu.feed(data)
                let snap = await emu.snapshot()
                self.snapshot = snap
            }
            // Stream finished — shell exited.
            guard let self else { return }
            let finalSnap = await emu.snapshot()
            self.isRunning = false
            self.snapshot = finalSnap
        }
    }

    /// Terminates the current session cleanly.
    public func stopSession() async {
        pumpTask?.cancel()
        pumpTask = nil
        resizeLoop?.cancel()
        resizeLoop = nil
        resizePending = false
        await session?.terminate()
        session = nil
        emulator = nil
        isRunning = false
    }

    // MARK: - TerminalLifecycle (2.6)

    /// Terminates all active PTY sessions (called by `AppDelegate` on quit).
    ///
    /// `AppDelegate.applicationShouldTerminate` awaits this method before
    /// replying `.terminateLater`.
    public func killAllPTYs() async {
        await stopSession()
    }

    // MARK: - Keyboard input

    /// Sends raw bytes to the shell's stdin.
    ///
    /// On write failure the keystroke is silently discarded and a non-fatal
    /// warning is logged. Does not surface an alert (non-blocking per spec).
    public func send(_ bytes: Data) {
        guard let sess = session else { return }
        Task {
            do {
                try await sess.send(bytes)
            } catch {
                // PTY write failed (slave closed) — discard keystroke, mark for restart.
                await MainActor.run { self.isRunning = false }
            }
        }
    }

    // MARK: - Workspace directory sync (2.2)

    /// Called by `TerminalView.onChange(of:)` when `AppState.activeWorkspaceDirectory`
    /// changes. Writes a `cd` command to the running shell.
    ///
    /// Terminal is a read-only consumer of `AppState` — it never mutates it (SR-1).
    public func syncWorkingDirectory(_ url: URL?) {
        guard let url else { return }
        guard url != currentWorkingDirectory else { return }
        currentWorkingDirectory = url
        let cd = "cd \(url.path.shellEscaped)\n"
        guard let data = cd.data(using: .utf8) else { return }
        send(data)
    }

    // MARK: - Resize

    /// Notifies the PTY and emulator of a terminal resize.
    ///
    /// Stores the last-known dimensions so they can be re-applied when a new
    /// session starts. Resizes both the PTY (`TIOCSWINSZ`) and the emulator grid,
    /// then refreshes the published snapshot.
    ///
    /// Resizes are **coalesced** (ISS-078): a rapid drag spawns many `resize` calls,
    /// but only one apply loop runs at a time, and it always applies the most recent
    /// `lastCols`/`lastRows`. This guarantees the grid never settles at a stale size,
    /// which an unordered detached `Task` per call could not (the tasks could complete
    /// out of order). Flags are mutated only on the main actor, so there is no race.
    public func resize(cols: UInt16, rows: UInt16) {
        lastCols = cols
        lastRows = rows
        guard session != nil else { return }
        resizePending = true
        guard resizeLoop == nil else { return }  // a loop is already draining
        resizeLoop = Task { [weak self] in
            guard let self else { return }
            while self.resizePending {
                self.resizePending = false
                let cols = self.lastCols
                let rows = self.lastRows
                await self.session?.resize(cols: cols, rows: rows)
                await self.emulator?.resize(cols: Int(cols), rows: Int(rows))
                if let snap = await self.emulator?.snapshot() {
                    self.snapshot = snap
                }
            }
            self.resizeLoop = nil
        }
    }

    // MARK: - Alert dismissal

    /// Dismisses the currently pending alert.
    public func dismissAlert() {
        pendingAlert = nil
    }

    // MARK: - TerminalCommanding (2.6)

    public func sendText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        send(data)
    }

    public func sendCommand(_ command: String) {
        guard let data = (command + "\n").data(using: .utf8) else { return }
        send(data)
    }

    public func currentSelectionText() -> String? {
        terminalTextView?.selectionText()
    }

    public func lastCommandOutput() -> String? {
        // Read from the cached @Published snapshot (updated by the pump task).
        snapshot?.lastCommandOutput
    }
}
