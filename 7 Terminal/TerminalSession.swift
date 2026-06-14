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

    /// Optional observer for AI-detection output line monitoring.
    /// Set by `SputnikApp` at launch. Weak reference prevents retain cycles (SW-2).
    /// Nonisolated because actors cannot hold weak references to non-sendable types.
    public nonisolated(unsafe) weak var aiOutputObserver: TerminalAIOutputObserving?

    // MARK: - Private storage

    private var masterFD: Int32?
    private var pid: pid_t?
    private var exitSource: DispatchSourceProcess?
    private var hasExited = false
    private var channel: PTYChannel?
    private let continuation: AsyncStream<Data>.Continuation

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
        continuation.finish()
    }

    // MARK: - Session control

    /// Opens the PTY and launches Zsh with `workingDirectory` as its CWD.
    ///
    /// - Parameter workingDirectory: The folder to `cd` into on launch. Uses the
    ///   user's home directory if `nil`.
    /// - Throws: `SputnikError.hardwareAccessDenied` if the PTY cannot be opened;
    ///   `SputnikError.processLaunchFailed` if Zsh cannot be started.
    public func start(workingDirectory: URL? = nil) async throws {
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
                environment: buildEnvironment()
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
            onLine: { [weak self] line in
                guard let self else { return }
                // The observer is MainActor-isolated; main is serial so lines stay
                // ordered. aiOutputObserver is nonisolated(unsafe) weak.
                DispatchQueue.main.async { self.aiOutputObserver?.observe(line: line) }
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

        // 5. Inject OSC 133 shell-integration hooks after a brief delay
        // so Zsh has finished loading .zshrc / .zprofile.
        injectShellIntegration(after: 300_000_000)  // 300 ms delay
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

    /// Injects OSC 133 shell-integration hooks after the specified nanosecond delay.
    /// The hooks append to `precmd_functions` and `preexec_functions` so the user's
    /// own `.zshrc` hooks are preserved.
    private func injectShellIntegration(after nanoseconds: UInt64) {
        Task(priority: .background) { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self else { return }
            let snippet = """
                __sputnik_precmd() {
                    printf '\\033]133;D;%s\\007' "$?"
                    printf '\\033]133;A\\007'
                }
                __sputnik_preexec() {
                    printf '\\033]133;B\\007'
                    printf '\\033]133;C\\007'
                }
                preexec_functions+=(__sputnik_preexec)
                precmd_functions+=(__sputnik_precmd)
                """
            guard let data = (snippet + "\n").data(using: .utf8) else { return }
            try? await self.send(data)
        }
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
        continuation.finish()
    }

    private func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        return env
    }
}
