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
