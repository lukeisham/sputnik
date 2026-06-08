import Foundation
import Observation

/// The single, thread-safe source of truth for the app's global runtime state.
///
/// Created once in `SputnikApp` and injected into the view hierarchy via
/// `.environment(appState)`. All modules read from it through `@Environment`.
///
/// **Writers:**
/// - `InterPanelRouter` (2.1) is the sole writer for document state (`openDocuments`,
///   `activeDocumentID`). External modules must never mutate these directly.
/// - The toolbar writes `focusMode` directly (UI gesture, same Foundation layer).
/// - `DocumentTabBar` (2.4) writes `activeDocumentID` on tab-tap (same Foundation layer).
///
/// **Threading:** `AppState` is `@MainActor` — all reads and writes happen on the main
/// thread. Background file-system events must hop to `@MainActor` before mutating any
/// property; the actor isolation makes this a compile-time guarantee (SW-1, SR-4).
@Observable
@MainActor
public final class AppState {

    // MARK: - Workspace

    /// The folder currently shown in the File Tree and used as the terminal working directory.
    /// `nil` until the user opens a project folder.
    public var activeWorkspaceDirectory: URL?

    // MARK: - Multi-document tab model (resolves ISS-005)

    /// Ordered list of all open document sessions; drives the tab bar.
    ///
    /// Append / remove via `InterPanelRouter.open(_:)` and `close(_:)` only.
    /// The order matches the visual left-to-right tab order.
    public var openDocuments: [DocumentSession] = []

    /// The `id` of the session currently visible in the editor and previews.
    /// `nil` when no documents are open (placeholder state).
    public var activeDocumentID: UUID?

    /// The currently active `DocumentSession`, derived from `activeDocumentID`.
    /// Returns `nil` when no documents are open. All panels that render file content
    /// observe this computed property.
    public var activeDocument: DocumentSession? {
        guard let id = activeDocumentID else { return nil }
        return openDocuments.first { $0.id == id }
    }

    // MARK: - Backward-compatible read accessors
    //
    // These derived properties let any code written against the old single-file model
    // continue to compile. They are read-only; do not add setters — all writes must
    // go through `InterPanelRouter` and the `openDocuments` / `activeDocumentID` path.

    /// The URL of the currently active document. `nil` when nothing is open or the
    /// active document is untitled.
    public var currentlyOpenFile: URL? {
        activeDocument?.url
    }

    /// The `FileType` of the currently active document. `.unknown` when nothing is open.
    public var currentlyOpenFileType: FileType {
        activeDocument?.fileType ?? .unknown
    }

    // MARK: - Focus mode

    /// The user's current focus mode; written by the toolbar, read by each panel.
    public var focusMode: FocusMode = .dev

    // MARK: - Init

    public init() {}
}
