import Foundation
import FoundationModule

/// Owns a single PTY master fd and a Zsh `Foundation.Process`.
///
/// Actor-isolated control (`start`/`send`/`resize`/`terminate`) serialises the
/// session's lifecycle (SW-1). The raw fd I/O itself runs through a `PTYChannel`
/// (a `DispatchSource` bridge — the MR-3 documented exception): reads are
/// event-driven rather than a blocking `availableData` loop (ISS-068), and writes
/// are queued non-blockingly so a full PTY buffer never wedges the actor (ISS-074).
/// The channel's callbacks capture `[weak self]`, so nothing holds the actor alive
/// for the I/O lifetime and the session deallocates when its owner releases it
/// (SW-2 — the canonical PTY infinite-loop leak risk).
///
/// Shell output is delivered as a **bounded** `AsyncStream<Data>` (ISS-073), and
/// the stream finishes on the PTY's natural EOF — produced by closing the parent's
/// slave copy right after launch (ISS-070).
///
/// The shell is launched via `PTYSpawn` (`forkpty`), which gives it a controlling
/// terminal so job control, Ctrl-C, and SIGWINCH work (ISS-071). `forkpty` performs
/// the MR-5 PTY-open sequence inside libc and wires the slave onto the child's
/// stdio as its controlling tty — the documented departure from MR-4's
/// "use `Foundation.Process`" guidance.
public actor TerminalSession {

    // MARK: - Types

    /// The current lifecycle state of the session.
    public enum SessionState: Sendable {
        case idle
        case running
        case exited(exitCode: Int32)
        case failed(SputnikError)
    }

    // MARK: - Public state

    /// Continuously emits raw bytes read from the PTY master fd.
    ///
    /// Finishes when the shell exits or the PTY is closed.
    public let outputStream: AsyncStream<Data>

    private(set) public var state: SessionState = .idle

    // MARK: - Private storage

    private var masterFD: Int32?
    private var pid: pid_t?
    private var exitSource: DispatchSourceProcess?
    private var hasExited = false
    private var channel: PTYChannel?
    private let continuation: AsyncStream<Data>.Continuation

    /// Temp directory holding the `ZDOTDIR` shim files for this session, removed on
    /// teardown. `nil` when no shim was installed (creation failed → the shell was
    /// launched without shell integration, ISS-077).
    private var shimDirectory: URL?

    /// Upper bound on buffered output chunks. Bounding the stream caps raw `Data`
    /// growth when a fast producer (e.g. `cat` of a large file) outruns the
    /// emulator pump; `.bufferingNewest` keeps the most recent output — the correct
    /// final screen state — and drops the oldest under flood (ISS-073). With 64 KiB
    /// read chunks this caps the queue at roughly 8 MiB.
    private static let outputBufferLimit = 128

    // MARK: - Init

    public init() {
        var cont: AsyncStream<Data>.Continuation!
        self.outputStream = AsyncStream(
            bufferingPolicy: .bufferingNewest(Self.outputBufferLimit)
        ) { cont = $0 }
        self.continuation = cont
    }

    deinit {
        // Safety net: if the owner drops the session without calling `terminate()`,
        // kill any surviving shell and cancel the Dispatch sources so neither the
        // process, the sources, nor the master fd leak (SW-2 / spec 7.5).
        // `teardown()` extends the channel's own lifetime until it has run.
        if let pid, !hasExited { kill(pid, SIGKILL) }
        exitSource?.cancel()
        channel?.teardown()
        if let shimDirectory { try? FileManager.default.removeItem(at: shimDirectory) }
        continuation.finish()
    }

    // MARK: - Session control

    /// Opens the PTY and launches Zsh with `workingDirectory` as its CWD.
    ///
    /// - Parameters:
    ///   - workingDirectory: The folder to `cd` into on launch. Uses the user's
    ///     home directory if `nil`.
    ///   - observer: Optional AI-detection line observer. Captured **weakly** in the
    ///     PTY-channel line callback rather than stored in a shared mutable property,
    ///     so the reference is never read/written across threads (ISS-076). The
    ///     protocol is `Sendable`, so the weak capture is race-free without an
    ///     `unsafe` annotation; conformers make `observe(line:)` thread-safe.
    /// - Throws: `SputnikError.hardwareAccessDenied` if the PTY cannot be opened;
    ///   `SputnikError.processLaunchFailed` if Zsh cannot be started.
    public func start(
        workingDirectory: URL? = nil,
        observer: TerminalAIOutputObserving? = nil
    ) async throws {
        guard case .idle = state else { return }

        // 1. Spawn Zsh on a fresh PTY with the slave as its controlling terminal
        //    (ISS-071). `forkpty` performs the MR-5 PTY-open inside libc; the child
        //    holds the only slave fds, so the master sees a natural EOF once the
        //    child (and its descendants) exit (preserves 7a's EOF teardown). This
        //    replaces the old Foundation.Process launch (MR-4).
        let cwd = (workingDirectory ?? URL(fileURLWithPath: NSHomeDirectory())).path
        let launched: PTYSpawn.Launched
        do {
            launched = try PTYSpawn.spawnLoginShell(
                executable: "/bin/zsh",
                arguments: ["--login"],
                workingDirectory: cwd,
                environment: buildEnvironment(installShellIntegration: true)
            )
        } catch let err as SputnikError {
            state = .failed(err)
            throw err
        }
        let childPID = launched.pid
        self.pid = childPID
        self.masterFD = launched.masterFD
        state = .running

        // 3. Detect the shell's exit and reap it (replaces Process.terminationHandler).
        //    DispatchSourceProcess(.exit) fires on NOTE_EXIT; `waitpid` is the sole
        //    reap site, so the SIGKILL escalation in `terminate()` can't double-reap.
        let source = DispatchSource.makeProcessSource(
            identifier: childPID, eventMask: .exit, queue: .global())
        source.setEventHandler { [weak self] in
            var status: Int32 = 0
            let reaped = waitpid(childPID, &status, 0)
            let code = reaped == childPID ? PTYSpawn.exitCode(fromWaitStatus: status) : 0
            guard let self else { return }
            Task { await self.handleExit(code: code) }
        }
        self.exitSource = source
        source.resume()

        // 4. Start event-driven PTY I/O. Callbacks capture [weak self] so the
        // channel never keeps the actor alive on its own (SW-2). The continuation
        // is captured directly so output yields don't need to hop onto the actor.
        let channel = PTYChannel(
            fd: launched.masterFD,
            onData: { [continuation] data in
                continuation.yield(data)
            },
            onLine: { [weak observer] line in
                // Captured weakly so the observer never keeps the session alive and
                // is never stored in shared mutable state (ISS-076). The callback runs
                // on the channel's serial queue, so lines arrive in order; `observe`
                // is `Sendable`/thread-safe (it yields into an AsyncStream).
                observer?.observe(line: line)
            },
            onEOF: { [continuation] in
                // Slave closed → the shell is exiting. Finishing the stream ends the
                // manager's pump; the authoritative exit code + teardown arrive via
                // the exit source. (No cleanup here, or it would cancel the exit
                // source before it can reap — ISS-071 must not regress 7a's reaping.)
                continuation.finish()
            }
        )
        self.channel = channel
        channel.activate()

        // Shell integration is now installed deterministically at startup via the
        // ZDOTDIR shim wired into the child environment (see buildEnvironment), not
        // by writing a snippet to stdin after a fixed delay — which raced slow rc
        // loads and echoed into the first prompt (ISS-077).
    }

    /// Queues bytes for the PTY master fd (i.e. to Zsh's stdin).
    ///
    /// The write is non-blocking: bytes are handed to the `PTYChannel`, which
    /// drains them off the actor and waits for writability on a full buffer rather
    /// than blocking (ISS-074).
    ///
    /// - Throws: `SputnikError.ptyWriteFailed` if the session has no live channel.
    public func send(_ bytes: Data) throws {
        guard let channel else {
            throw SputnikError.ptyWriteFailed
        }
        channel.enqueueWrite(bytes)
    }

    /// Notifies the PTY of a terminal resize so Zsh can reflow output. With a
    /// controlling terminal, `TIOCSWINSZ` also delivers SIGWINCH to the foreground
    /// process group (ISS-071).
    public func resize(cols: UInt16, rows: UInt16) {
        guard let fd = masterFD, fd >= 0 else { return }
        var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(fd, TIOCSWINSZ, &ws)
    }

    /// Terminates the Zsh process: SIGTERM → poll for exit → SIGKILL escalation →
    /// close PTY.
    ///
    /// A shell that traps or is slow to handle SIGTERM is force-killed after the
    /// poll window so no orphaned shell survives (spec 7.5, ISS-072). Reaping is
    /// done by the exit source's `waitpid`; this method only signals and waits for
    /// `hasExited` to flip. Safe to call multiple times; subsequent calls are no-ops.
    public func terminate() async {
        guard let pid, !hasExited else {
            cleanupPTY()
            return
        }
        kill(pid, SIGTERM)

        // Poll for graceful exit up to ~2 s before escalating (ISS-072).
        await waitForExit(timeoutNanoseconds: 2_000_000_000)

        if !hasExited {
            kill(pid, SIGKILL)
            // SIGKILL is immediate; give the exit source a moment to reap.
            await waitForExit(timeoutNanoseconds: 1_000_000_000)
        }

        cleanupPTY()
    }

    /// Awaits `hasExited` (set on this actor by the exit source) up to a timeout.
    private func waitForExit(timeoutNanoseconds: UInt64) async {
        let pollInterval: UInt64 = 50_000_000  // 50 ms
        var waited: UInt64 = 0
        while !hasExited && waited < timeoutNanoseconds {
            try? await Task.sleep(nanoseconds: pollInterval)
            waited += pollInterval
        }
    }

    // MARK: - Private helpers

    /// Removes this session's `ZDOTDIR` shim directory, if one was installed.
    /// Idempotent — nulls out the reference so a second call is a no-op. Called on
    /// teardown (after the shell has read its startup files), never right after
    /// spawn, so a slow login shell still finds the files (ISS-077).
    private func removeShimDirectory() {
        guard let directory = shimDirectory else { return }
        shimDirectory = nil
        try? FileManager.default.removeItem(at: directory)
    }

    /// Called by the exit source once the shell has exited and been reaped.
    /// Idempotent via the `hasExited` flag.
    private func handleExit(code: Int32) {
        guard !hasExited else { return }
        hasExited = true
        state = .exited(exitCode: code)
        cleanupPTY()
    }

    /// Tears down the exit source and channel (the channel closes the master fd
    /// from its read source's cancel handler) and finishes the output stream.
    /// Idempotent — called from `terminate()` and `handleExit`.
    private func cleanupPTY() {
        exitSource?.cancel()
        exitSource = nil
        pid = nil
        // The channel owns the master fd once activated and closes it from its read
        // source's cancel handler, so just drop our reference — never double-close.
        channel?.teardown()
        channel = nil
        masterFD = nil
        removeShimDirectory()
        continuation.finish()
    }

    private func buildEnvironment(installShellIntegration: Bool) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"

        guard installShellIntegration else { return env }

        // Install the OSC 133 shell-integration hooks via a ZDOTDIR shim. The shim
        // re-sources the user's real dotfiles and appends the hooks after `.zshrc`,
        // so they always install (no race) and never echo into the first prompt
        // (ISS-077). On any I/O failure we log and launch *without* integration —
        // a working shell must never be blocked by this enhancement (SR-2).
        do {
            let directory = try ZDOTDIRShim.install()
            shimDirectory = directory
            // The user's real ZDOTDIR (their own if set, else $HOME); the shim
            // restores this before sourcing each real startup file.
            let realZDOTDIR = env["ZDOTDIR"] ?? NSHomeDirectory()
            env["ZDOTDIR"] = directory.path
            env[ZDOTDIRShim.shimDirVar] = directory.path
            env[ZDOTDIRShim.userZDOTDIRVar] = realZDOTDIR
        } catch {
            SputnikLogger.terminal.warning(
                "ZDOTDIR shim install failed; launching without shell integration: \(error.localizedDescription, privacy: .public)")
        }
        return env
    }
}
