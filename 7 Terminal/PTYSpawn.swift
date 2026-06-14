import Foundation
import Darwin
import FoundationModule

/// Launches the Zsh child with a PTY slave as its **controlling terminal**.
///
/// `Foundation.Process` cannot establish a controlling terminal, so job control,
/// interrupts (Ctrl-C → SIGINT to the foreground process group), and resize
/// notifications (SIGWINCH) never reach the running command (ISS-071).
///
/// We use `forkpty(3)`, which atomically opens a PTY pair (the MR-5
/// `posix_openpt → grantpt → unlockpt` sequence, performed inside libc), forks,
/// and in the child calls `setsid` + `ioctl(TIOCSCTTY)` and wires the slave onto
/// fds 0/1/2 — the controlling-terminal setup that `posix_spawn` cannot express
/// (no `ioctl` file action) and that `Foundation.Process` does not do. The child
/// then only `chdir`s and `execve`s.
///
/// **Fork safety:** after `forkpty` returns in the child, this code calls *only*
/// async-signal-safe C functions (`chdir`, `execve`, `_exit`) on C buffers built
/// **before** the fork — no Swift allocation, ARC, or Foundation runs in the child.
///
/// This is the documented departure from the original MR-4 "use `Foundation.Process`"
/// guidance; see `Vibe_Coding_Rules.md` (MR-4) and the Module Guide.
enum PTYSpawn {

    /// The result of a successful launch: the child pid and the PTY **master** fd
    /// (the parent reads shell output from / writes keystrokes to this fd).
    struct Launched {
        let pid: pid_t
        let masterFD: Int32
    }

    /// Spawns the login shell on a fresh PTY whose slave is the child's controlling
    /// terminal.
    ///
    /// - Throws: `SputnikError.hardwareAccessDenied` if the PTY pair cannot be
    ///   opened; `SputnikError.processLaunchFailed` if the fork fails.
    static func spawnLoginShell(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String],
        cols: UInt16 = 80,
        rows: UInt16 = 24
    ) throws -> Launched {

        // --- Build all C buffers in the parent (no allocation after the fork).
        let executableC = strdup(executable)
        let cwdC = strdup(workingDirectory)

        let argvValues = [executable] + arguments
        let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
            .allocate(capacity: argvValues.count + 1)
        for (index, value) in argvValues.enumerated() { argv[index] = strdup(value) }
        argv[argvValues.count] = nil

        let envValues = environment.map { "\($0.key)=\($0.value)" }
        let envp = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
            .allocate(capacity: envValues.count + 1)
        for (index, value) in envValues.enumerated() { envp[index] = strdup(value) }
        envp[envValues.count] = nil

        func freeBuffers() {
            free(executableC)
            free(cwdC)
            for index in 0..<argvValues.count { free(argv[index]) }
            argv.deallocate()
            for index in 0..<envValues.count { free(envp[index]) }
            envp.deallocate()
        }

        // --- forkpty: open the PTY, fork, and set up the controlling terminal.
        var masterFD: Int32 = -1
        var window = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        let pid = withUnsafeMutablePointer(to: &window) { windowPtr -> pid_t in
            let forked = forkpty(&masterFD, nil, nil, windowPtr)
            if forked == 0 {
                // ===== CHILD — async-signal-safe calls only =====
                _ = chdir(cwdC)
                execve(executableC, argv, envp)
                _exit(127)  // execve only returns on failure
                // ===== end CHILD =====
            }
            return forked
        }

        // ===== PARENT =====
        freeBuffers()
        guard pid > 0 else {
            throw SputnikError.processLaunchFailed(
                detail: "forkpty failed: \(String(cString: strerror(errno)))")
        }
        return Launched(pid: pid, masterFD: masterFD)
    }

    /// Decodes a `waitpid` status into a conventional exit code: the raw exit
    /// status for a normal exit, or `128 + signal` for a signal-terminated child.
    static func exitCode(fromWaitStatus status: Int32) -> Int32 {
        let termSignal = status & 0x7F
        if termSignal == 0 {
            return (status >> 8) & 0xFF  // WEXITSTATUS
        }
        return 128 + termSignal
    }
}
