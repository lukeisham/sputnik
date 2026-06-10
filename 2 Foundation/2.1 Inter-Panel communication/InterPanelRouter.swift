import Foundation

/// Contract for routing file-open, file-close, and directory-change events between panels.
///
/// Foundation registers this protocol; the concrete implementation lives at the app-assembly
/// layer (never inside Foundation) so modules stay decoupled from each other (SR-1).
///
/// All methods are `@MainActor` because routing decisions mutate `AppState` synchronously.
@MainActor
public protocol InterPanelRouter: AnyObject {

    /// An `AsyncStream` of `PanelEvent` values; any module can observe it to react to
    /// routing decisions without holding a direct reference to the router (SW-1).
    var events: AsyncStream<PanelEvent> { get }

    // MARK: - Document lifecycle

    /// Opens `file` in the appropriate panel using **find-or-create** semantics:
    ///
    /// 1. If a `DocumentSession` with this URL already exists in `AppState.openDocuments`,
    ///    that session is made active and its hosting panel is raised — no duplicate tab.
    /// 2. Otherwise a new `DocumentSession` is created, appended to `openDocuments`,
    ///    and made active. The `FileType` is classified from the URL extension.
    ///
    /// Preview routing by `FileType`: `.html` activates module 8, `.markdown` activates
    /// module 4, `.pdf` and `.image` activate module 5, and so on.
    ///
    /// - Parameter file: The `URL` of the file to open. Must be a file URL.
    func open(_ file: URL) async

    /// Closes the document session identified by `id`.
    ///
    /// Behaviour:
    /// - If `session.isDirty` is `true`, a `SputnikAlert` unsaved-changes prompt is raised
    ///   before discarding; the session is only removed if the user confirms.
    /// - After removal, `activeDocumentID` is updated to the nearest neighbouring tab,
    ///   or `nil` if the list is now empty (returning the UI to an empty placeholder state).
    ///
    /// - Parameter id: The `UUID` of the `DocumentSession` to close.
    func close(_ id: UUID) async

    // MARK: - Directory sync

    /// Updates `AppState.activeWorkspaceDirectory` and broadcasts a `.directoryChanged`
    /// event so the Terminal (module 7) can `cd` to the new directory.
    ///
    /// - Parameter url: The new workspace directory URL.
    func syncDirectory(_ url: URL)
}
