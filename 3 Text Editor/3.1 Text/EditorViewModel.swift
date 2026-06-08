import Foundation
import Observation

/// Centralised, thread-safe editor state for module 3.
///
/// All sub-modules in module 3 read or mutate this view model. Keeping the mode,
/// gating flags, and file URL here (not scattered across sub-modules) honours SR-1
/// ("module owns its state") and matches the module guides, which explicitly place
/// `htmlModeActive` and `spellCheckActive` in `EditorViewModel`.
@Observable
@MainActor
public final class EditorViewModel {

    // MARK: - Document identity

    /// The URL of the currently open file. `nil` for an untitled buffer.
    public var fileURL: URL?

    /// `true` when unsaved changes exist since the last clean file write.
    public var isDirty: Bool = false

    // MARK: - Undo

    /// The shared undo manager for the `NSTextView`. Wired in by `EditorView`.
    public var undoManager: UndoManager?

    // MARK: - Mode

    /// The active editing mode; drives syntax highlighting and sub-module activation.
    public var mode: EditorMode = .plainText

    // MARK: - Gating flags (set by sub-modules after per-file analysis)

    /// Set by `HTMLDocTypeGuard` when the open file begins with `<!DOCTYPE html>`.
    /// Enables HTML suggestions and the "Render as HTML" menu item (3.4).
    public var htmlModeActive: Bool = false

    /// Set by `SpellCheckFileTypeGuard` when the file extension is `.txt` or `.md`.
    /// Enables real-time spell/grammar checking (3.5).
    public var spellCheckActive: Bool = false

    // MARK: - Init

    public init() {}

    // MARK: - Helpers

    /// Resets all per-file state when a new file is opened.
    ///
    /// Mode is inferred by the caller from the file extension; reset to `.plainText`
    /// as a safe default so no sub-module is left active from the previous session.
    public func resetForNewFile(url: URL?) {
        fileURL         = url
        isDirty         = false
        htmlModeActive  = false
        spellCheckActive = false
        mode            = .plainText
    }
}
