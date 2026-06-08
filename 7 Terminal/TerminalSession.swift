import Foundation

/// Owns a single PTY master `FileHandle` and a Zsh `Foundation.Process`.
///
/// All PTY I/O is serialised through actor isolation (SW-1). Shell output is
/// delivered as an `AsyncStream<Data>`. The long-lived output-reading
/// `Task(priority: .utility)` captures `[weak self]` so the session can
/// deallocate when the caller releases its reference (SW-2 — the canonical
/// PTY infinite-loop leak risk).
///
/// Zsh `standardInput/Output/Error` are bound to the PTY **slave `FileHandle`**,
/// never a `Pipe` (MR-4). The PTY is opened via the full `posix_openpt →
/// grantpt → unlockpt → ptsname` sequence in `PTYHandle` (MR-5).
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

    private var ptyHandle:  PTYHandle?
    private var process:    Process?
    private let continuation: AsyncStream<Data>.Continuation

    // MARK: - Init

    public init() {
        var cont: AsyncStream<Data>.Continuation!
        self.outputStream = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
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

        // 1. Open the PTY pair (MR-5).
        let pty: PTYHandle
        do {
            pty = try PTYHandle()
        } catch let err as SputnikError {
            state = .failed(err)
            throw err
        }
        self.ptyHandle = pty

        // 2. Open the slave device for the child process.
        guard let slaveHandle = FileHandle(forUpdatingAtPath: pty.slavePath) else {
            pty.close()
            self.ptyHandle = nil
            let err = SputnikError.hardwareAccessDenied(detail: "Could not open slave PTY at \(pty.slavePath)")
            state = .failed(err)
            throw err
        }

        // 3. Configure and launch Zsh (MR-4 — bind to slave FileHandle, not a Pipe).
        let zsh = Process()
        zsh.executableURL    = URL(fileURLWithPath: "/bin/zsh")
        zsh.arguments        = ["--login"]
        zsh.standardInput    = slaveHandle   // MR-4
        zsh.standardOutput   = slaveHandle   // MR-4
        zsh.standardError    = slaveHandle   // MR-4
        zsh.currentDirectoryURL = workingDirectory ?? URL(
            fileURLWithPath: NSHomeDirectory()
        )
        zsh.environment = buildEnvironment(slavePath: pty.slavePath)

        // Notify when Zsh exits.
        zsh.terminationHandler = { [weak self] proc in
            guard let self else { return }
            Task { await self.handleExit(code: proc.terminationStatus) }
        }

        do {
            try zsh.launch()
        } catch {
            pty.close()
            self.ptyHandle = nil
            let err = SputnikError.processLaunchFailed(detail: error.localizedDescription)
            state = .failed(err)
            throw err
        }

        self.process = zsh
        state = .running

        // 4. Start the PTY-output reading loop.
        // The Task captures [weak self] to prevent retaining the actor indefinitely (SW-2).
        startReadingOutput(from: pty.master)
    }

    /// Writes bytes to the PTY master fd (i.e. to Zsh's stdin).
    ///
    /// - Throws: `SputnikError.ptyWriteFailed` if the master fd is no longer writable.
    public func send(_ bytes: Data) throws {
        guard let master = ptyHandle?.master else {
            throw SputnikError.ptyWriteFailed
        }
        do {
            try master.write(contentsOf: bytes)
        } catch {
            throw SputnikError.ptyWriteFailed
        }
    }

    /// Notifies the PTY of a terminal resize so Zsh can reflow output.
    public func resize(cols: UInt16, rows: UInt16) {
        guard let fd = ptyHandle?.master.fileDescriptor, fd >= 0 else { return }
        var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(fd, TIOCSWINSZ, &ws)
    }

    /// Terminates the Zsh process cleanly: SIGTERM → wait → close master fd → nil process.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops.
    public func terminate() async {
        guard let proc = process, proc.isRunning else {
            cleanupPTY()
            return
        }
        proc.terminate()          // SIGTERM
        // Give the process a moment to exit gracefully before closing the fd.
        try? await Task.sleep(nanoseconds: 150_000_000) // 150 ms
        cleanupPTY()
    }

    // MARK: - Private helpers

    private func startReadingOutput(from master: FileHandle) {
        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            while true {
                let data: Data
                do {
                    data = try master.availableData
                } catch {
                    break
                }
                guard !data.isEmpty else { break }
                await self.emit(data)
            }
            await self.continuation.finish()
        }
    }

    private func emit(_ data: Data) {
        continuation.yield(data)
    }

    private func handleExit(code: Int32) {
        state = .exited(exitCode: code)
        cleanupPTY()
    }

    private func cleanupPTY() {
        process = nil
        ptyHandle?.close()
        ptyHandle = nil
    }

    private func buildEnvironment(slavePath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"]      = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        // Ensure the slave path is available as the controlling terminal.
        env["SSH_TTY"]   = slavePath
        return env
    }
}
