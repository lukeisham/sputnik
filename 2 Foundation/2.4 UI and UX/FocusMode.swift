import Foundation

/// The user's current focus-mode choice, which hides panels to reduce visual noise.
///
/// Stored in `AppState` (2.2); the toolbar writes it, panels read it via `@Environment`.
public enum FocusMode: String, Codable, Sendable, CaseIterable {
    /// All panels are visible (the default working state).
    case dev
    /// Hides the File Tree and the Terminal strip; intended for distraction-free writing.
    case writer
    /// Hides the Text Editor and the Terminal strip; intended for reviewing rendered output.
    case reader
}
