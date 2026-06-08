import Foundation

/// Opens a pseudo-terminal using the POSIX sequence
/// `posix_openpt → grantpt → unlockpt → ptsname` and vends the resulting
/// master `FileHandle` together with the slave device path.
///
/// Provides a single `close()` to release the master fd. All POSIX calls
/// are checked; failure throws `SputnikError.hardwareAccessDenied` rather
/// than force-unwrapping (MR-5, SR-2).
public final class PTYHandle {

    // MARK: - Public state

    /// The master side of the PTY — write keystrokes here, read shell output.
    public let master: FileHandle

    /// Filesystem path to the slave device (e.g. `/dev/ttys003`).
    public let slavePath: String

    // MARK: - Init

    /// Opens a new PTY pair.
    ///
    /// - Throws: `SputnikError.hardwareAccessDenied` if any POSIX call fails.
    public init() throws {
        // 1. Open a master PTY fd.
        let masterFD = posix_openpt(O_RDWR | O_NOCTTY)
        guard masterFD >= 0 else {
            throw SputnikError.hardwareAccessDenied(
                detail: "posix_openpt failed: \(String(cString: strerror(errno)))"
            )
        }

        // 2. Grant access to the slave device.
        guard grantpt(masterFD) == 0 else {
            Darwin.close(masterFD)
            throw SputnikError.hardwareAccessDenied(
                detail: "grantpt failed: \(String(cString: strerror(errno)))"
            )
        }

        // 3. Unlock the slave device.
        guard unlockpt(masterFD) == 0 else {
            Darwin.close(masterFD)
            throw SputnikError.hardwareAccessDenied(
                detail: "unlockpt failed: \(String(cString: strerror(errno)))"
            )
        }

        // 4. Obtain the slave device path.
        guard let slaveNamePtr = ptsname(masterFD) else {
            Darwin.close(masterFD)
            throw SputnikError.hardwareAccessDenied(
                detail: "ptsname returned nil: \(String(cString: strerror(errno)))"
            )
        }
        let slavePathString = String(cString: slaveNamePtr)

        self.master    = FileHandle(fileDescriptor: masterFD, closeOnDealloc: false)
        self.slavePath = slavePathString
    }

    // MARK: - Teardown

    /// Closes the master fd.
    ///
    /// Call this from `TerminalSession.terminate()` after the Zsh process has exited.
    public func close() {
        Darwin.close(master.fileDescriptor)
    }
}
