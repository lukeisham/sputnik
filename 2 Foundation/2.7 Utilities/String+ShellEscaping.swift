import Foundation

extension String {
    /// Returns a shell-safe version of the string, single-quoted.
    ///
    /// Used by `TerminalManager.syncWorkingDirectory` and
    /// `EditorViewModel.runCurrentFileInTerminal` to safely interpolate
    /// file paths into shell commands without risking injection.
    public var shellEscaped: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
