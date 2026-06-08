import Foundation

/// A typed error used to drive every alert dialog in Sputnik.
///
/// All error paths that surface a dialog to the user produce a `SputnikAlert` so
/// presentation is consistent and testable.
public enum SputnikAlert: Error, Sendable {
    /// A file was opened whose type is not handled by any registered panel.
    case unsupportedFileType(URL)
    /// A file could not be read from disk.
    case fileReadFailed(URL, underlyingError: String)
    /// A file could not be written to disk.
    case fileWriteFailed(URL, underlyingError: String)
    /// The layout state on disk was corrupt and has been reset to defaults.
    case layoutRestoreFailed
    /// A crash-recovery file was found for the given filename.
    case recoveryAvailable(filename: String)
    /// A custom, one-off message for cases not covered by the enum above.
    case custom(title: String, message: String)
}

public extension SputnikAlert {
    /// A short, human-readable title suitable for an alert headline.
    var title: String {
        switch self {
        case .unsupportedFileType:    return "Unsupported File"
        case .fileReadFailed:         return "Could Not Open File"
        case .fileWriteFailed:        return "Could Not Save File"
        case .layoutRestoreFailed:    return "Layout Reset"
        case .recoveryAvailable:      return "Recover Unsaved Changes"
        case .custom(let t, _):       return t
        }
    }

    /// A longer description displayed in the alert body.
    var message: String {
        switch self {
        case .unsupportedFileType(let url):
            return ""\(url.lastPathComponent)" cannot be opened in Sputnik. Binary or unknown file types are not supported."
        case .fileReadFailed(let url, let err):
            return ""\(url.lastPathComponent)" could not be read.\n\nDetails: \(err)"
        case .fileWriteFailed(let url, let err):
            return ""\(url.lastPathComponent)" could not be saved.\n\nDetails: \(err)"
        case .layoutRestoreFailed:
            return "The saved window layout could not be restored and has been reset to the default arrangement."
        case .recoveryAvailable(let name):
            return "Sputnik found unsaved changes for "\(name)" from a previous session. Would you like to recover them?"
        case .custom(_, let m):
            return m
        }
    }
}
