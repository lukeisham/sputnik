import Foundation
import Observation

/// A single open document represented as an editor tab.
///
/// `DocumentSession` is the unit that a tab bar entry and a preview panel both point at.
/// Its stable `id` lets the UI track tabs across reordering and Save-As operations
/// without relying on the URL, which may be `nil` for untitled files or change on rename.
///
/// All mutations are `@MainActor`-isolated; the shared `AppState` (module 2.2) owns the
/// authoritative ordered list of sessions. Modules must never create or discard sessions
/// directly — they go through `InterPanelRouter.open(_:)` and `close(_:)` (module 2.1).
@Observable
@MainActor
public final class DocumentSession: Identifiable {

    /// Stable identity for this tab, assigned at creation and never changed.
    public let id: UUID

    /// The file URL backing this document. `nil` for untitled (new, unsaved) documents.
    /// Changes on Save As; the `id` remains the same.
    public var url: URL?

    /// The MIME/extension classification of this document, used by panels to decide
    /// whether to render it (e.g. HTML Preview only activates for `.html` sessions).
    public var fileType: FileType

    /// The current text content of this document, kept in sync with the editor's
    /// text storage (module 3) and consumed by preview panels (modules 4, 8).
    ///
    /// For binary or oversized files (`fileType == .binary`), this is an empty string;
    /// the file is never loaded into memory here.
    public var text: String

    /// `true` when `text` has been modified since the last save or since the document
    /// was opened. Written by the text editor (module 3); read by the close path to
    /// decide whether to show an unsaved-changes prompt.
    public var isDirty: Bool

    // MARK: - Init

    /// Creates a new document session.
    ///
    /// - Parameters:
    ///   - id:       Stable identity. Defaults to a fresh `UUID`.
    ///   - url:      The file URL, or `nil` for an untitled document.
    ///   - fileType: The type classification of the document.
    ///   - text:     Initial text content. Defaults to an empty string.
    ///   - isDirty:  Whether the document starts with unsaved changes. Defaults to `false`.
    public init(
        id: UUID = UUID(),
        url: URL?,
        fileType: FileType,
        text: String = "",
        isDirty: Bool = false
    ) {
        self.id = id
        self.url = url
        self.fileType = fileType
        self.text = text
        self.isDirty = isDirty
    }
}
