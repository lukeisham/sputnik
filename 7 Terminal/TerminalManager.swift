import Foundation
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
public final class TerminalManager: ObservableObject, TerminalLifecycle {

    // MARK: - Published UI state

    /// The latest grid snapshot to render. `nil` until the session starts.
    @Published public private(set) var snapshot: EmulatorSnapshot?

    /// Non-nil when the session has failed and a diagnostic should be shown.
    @Published public private(set) var pendingAlert: SputnikAlert?

    /// Whether the session is currently running.
    @Published public private(set) var isRunning: Bool = false

    // MARK: - AI output observer

    /// Weak reference to the Main AI output observer (Foundation 2.7).
    /// Set by `TerminalView` from the environment; forwarded to each new
    /// `TerminalSession` so Foundation can detect AI sessions without
    /// Terminal importing the monitor directly (SR-1).
    public nonisolated(unsafe) weak var aiOutputObserver: TerminalAIOutputObserving?

    // MARK: - Private storage

    private var session: TerminalSession?
    private var emulator: TerminalEmulator?
    private var pumpTask: Task<Void, Never>?
    private var currentWorkingDirectory: URL?

    // MARK: - Init / deinit

    public init() {}

    deinit {
        pumpTask?.cancel()
    }

    // MARK: - Session lifecycle

    /// Starts a new Zsh session rooted at `directory` using the supplied terminal `profile`.
    ///
    /// Cleans up any previous session first. On PTY or launch failure, sets
    /// `pendingAlert` for `TerminalView` to present via `SputnikAlert`.
    public func startSession(directory: URL? = nil, profile: TerminalProfile = .default) async {
        await stopSession()

        let sess = TerminalSession()
        sess.aiOutputObserver = self.aiOutputObserver
        let emu = TerminalEmulator(
            cols: 80, rows: 24,
            profile: profile
        )
        self.session = sess
        self.emulator = emu

        do {
            try await sess.start(workingDirectory: directory)
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

        // Pump the session's AsyncStream into the emulator and refresh snapshots.
        pumpTask = Task { [weak self] in
            guard let self else { return }
            for await data in sess.outputStream {
                await emu.feed(data)
                let snap = await emu.snapshot()
                await MainActor.run { self.snapshot = snap }
            }
            // Stream finished — shell exited.
            await MainActor.run {
                self.isRunning = false
                self.snapshot = await emu.snapshot()
            }
        }
    }

    /// Terminates the current session cleanly.
    public func stopSession() async {
        pumpTask?.cancel()
        pumpTask = nil
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

    /// Notifies the PTY of a terminal resize.
    public func resize(cols: UInt16, rows: UInt16) {
        guard let sess = session else { return }
        Task { await sess.resize(cols: cols, rows: rows) }
    }

    // MARK: - Alert dismissal

    /// Dismisses the currently pending alert.
    public func dismissAlert() {
        pendingAlert = nil
    }
}

// MARK: - String helper

extension String {
    /// Returns a shell-safe version of the string, single-quoted.
    fileprivate var shellEscaped: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
