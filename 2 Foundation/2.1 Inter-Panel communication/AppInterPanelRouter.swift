import AppKit
import Foundation

/// Concrete app-layer implementation of `InterPanelRouter`.
///
/// All `AppState` mutations delegate to existing `AppState` mutators (2.2) so this
/// class owns only routing logic, never file-IO or UI state.
///
/// Lifecycle:
///   1. `SputnikApp` creates the router as `@State private var router = AppInterPanelRouter()`.
///   2. `configure(appState:)` is called from `wireAppDelegate()` once Foundation objects
///      are ready — avoids the chicken-and-egg init ordering problem.
///   3. `ContentView` receives the router via `init(router:)` and calls `close(_:)` from
///      the `DocumentTabBar` callback.
@MainActor
public final class AppInterPanelRouter: InterPanelRouter {

    // MARK: - Event stream

    public let events: AsyncStream<PanelEvent>
    private let continuation: AsyncStream<PanelEvent>.Continuation

    // MARK: - Dependencies

    private weak var appState: AppState?

    // MARK: - Init

    /// `nonisolated` so `@State private var router = AppInterPanelRouter()` compiles
    /// without a MainActor hop in SputnikApp.init. Only `AsyncStream.makeStream` is
    /// called here — safe off-actor.
    public nonisolated init() {
        let (stream, continuation) = AsyncStream.makeStream(of: PanelEvent.self)
        self.events = stream
        self.continuation = continuation
    }

    /// Injects `AppState` after construction.
    /// Call from `SputnikApp.wireAppDelegate()` before any routing can occur.
    public func configure(appState: AppState) {
        self.appState = appState
    }

    // MARK: - InterPanelRouter

    public func open(_ file: URL) async {
        guard let appState else { return }
        let session = appState.openDocument(url: file)
        continuation.yield(.fileOpened(file, session.fileType))
    }

    public func close(_ id: UUID) async {
        guard let appState else { return }
        // Dirty-check: callers should confirm unsaved changes before invoking close().
        // A SputnikAlert guard will be threaded in once isDirty is surfaced back through
        // AppState by the text editor (ISS-NEW-A-dirty).
        appState.closeDocument(id)
    }

    /// Moves the active tab out of its current window and into a freshly created window.
    ///
    /// If the active document has unsaved changes, an unsaved-changes alert is shown first.
    /// Returns the new window's `UUID` so the caller can open its scene via `openWindow`;
    /// returns `nil` if there is no active document or the user cancels the confirmation.
    public func moveActiveTabToNewWindow() async -> UUID? {
        guard let appState,
              let sourceWS = appState.activeWindow,
              let docID = sourceWS.activeDocumentID,
              let session = sourceWS.activeDocument
        else { return nil }

        if session.isDirty {
            let confirmed = await confirmMoveUnsavedTab(filename: session.url?.lastPathComponent ?? "Untitled")
            guard confirmed else { return nil }
        }

        // Remove from the source window.
        sourceWS.openDocuments.removeAll { $0.id == docID }
        sourceWS.activeDocumentID = sourceWS.openDocuments.last?.id

        // Place the session in a new window.
        let newWS = appState.createWindow()
        newWS.openDocuments = [session]
        newWS.activeDocumentID = session.id
        return newWS.id
    }

    /// Shows a confirmation alert for moving a tab with unsaved changes.
    /// Returns `true` if the user confirmed the move.
    private func confirmMoveUnsavedTab(filename: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Unsaved Changes"
            alert.informativeText = "\u{201C}\(filename)\u{201D} has unsaved changes. Moving it will not discard them, but you will need to save from the new window."
            alert.addButton(withTitle: "Move")
            alert.addButton(withTitle: "Cancel")
            continuation.resume(returning: alert.runModal() == .alertFirstButtonReturn)
        }
    }

    public func syncDirectory(_ url: URL) {
        guard let appState else { return }
        appState.activeWorkspaceDirectory = url
        continuation.yield(.directoryChanged(url))
    }

    // MARK: - Lifecycle

    /// Finishes the event stream. Call on app termination to release subscribers.
    public func invalidate() {
        continuation.finish()
    }
}
