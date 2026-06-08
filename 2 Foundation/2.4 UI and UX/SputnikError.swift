import Foundation

/// Typed error for thrown failures in Sputnik.
///
/// Use for programmer-facing propagation via `throw`. At the presentation
/// boundary, convert to `SputnikAlert` for user-facing dialogs.
/// Resolves ISS-003: shared thrown-error type owned once in Foundation.
public enum SputnikError: Error, Sendable {

    /// A hardware resource (e.g. PTY master fd) could not be acquired.
    case hardwareAccessDenied(detail: String)

    /// A child process could not be launched.
    case processLaunchFailed(detail: String)

    /// A PTY write failed because the slave end was closed.
    case ptyWriteFailed
}

public extension SputnikError {
    /// A short description suitable for diagnostic output or `SputnikAlert.custom`.
    var localizedDescription: String {
        switch self {
        case .hardwareAccessDenied(let detail):
            return "Hardware access denied: \(detail)"
        case .processLaunchFailed(let detail):
            return "Process launch failed: \(detail)"
        case .ptyWriteFailed:
            return "PTY write failed — slave end is closed."
        }
    }
}
