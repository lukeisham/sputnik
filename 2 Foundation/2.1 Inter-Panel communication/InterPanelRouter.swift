import Foundation

/// Contract for routing file-open and directory-change events between panels.
///
/// Foundation registers this protocol; the concrete implementation lives at the app-assembly
/// layer (never inside Foundation) so modules stay decoupled from each other.
@MainActor
public protocol InterPanelRouter: AnyObject {
    /// An `AsyncStream` of `PanelEvent` values; any module can observe it to react to routing
    /// decisions without holding a reference to the router.
    var events: AsyncStream<PanelEvent> { get }

    /// Routes `file` to the appropriate panel based on its `FileType`.
    /// - Parameter file: The `URL` of the file the user wants to open.
    func open(_ file: URL) async

    /// Updates `AppState.activeWorkspaceDirectory` and broadcasts a `.directoryChanged` event.
    /// - Parameter url: The new workspace directory.
    func syncDirectory(_ url: URL)
}
