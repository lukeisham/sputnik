import Foundation

/// A persisted snapshot of one window's state, written to `windows.json` on quit
/// and read back on launch.
///
/// Each `WindowDescriptor` captures the window's stable UUID, its workspace
/// directory (the project folder shown in the File Tree and used by the Terminal),
/// the ordered list of open tab URLs, which tab was active, and the full per-window
/// `LayoutState` (panel arrangement, slot visibility, terminal pinned flag).
///
/// **Tab restoration detail:** Only persisted (non-untitled) tab URLs are stored.
/// Untitled documents are not saved; they are re-surfaced via crash recovery
/// (module 3.7) if they have unsaved content.
///
/// **Backward compatibility:** New fields added after the original schema decode
/// with a safe default when absent, so older `windows.json` files never cause
/// a total restore failure.
public struct WindowDescriptor: Codable, Sendable {

    /// The stable UUID used as the SwiftUI scene value for this window.
    public var id: UUID

    /// The project folder shown in this window's File Tree and used as its
    /// Terminal working directory. `nil` when no folder has been opened yet.
    public var workspaceDirectoryURL: URL?

    /// Ordered URLs of all saved (non-untitled) open tabs, left-to-right.
    /// May be empty if the window had no persisted tabs.
    public var openTabURLs: [URL]

    /// The URL of the tab that was active when the app last quit, or `nil`
    /// if the active tab was untitled or no document was active.
    public var activeDocumentURL: URL?

    /// Per-window panel arrangement, slot visibility, terminal pinned flag,
    /// and recent-files list.
    public var layout: LayoutState

    // MARK: - Init

    public init(
        id: UUID,
        workspaceDirectoryURL: URL?,
        openTabURLs: [URL],
        activeDocumentURL: URL?,
        layout: LayoutState
    ) {
        self.id = id
        self.workspaceDirectoryURL = workspaceDirectoryURL
        self.openTabURLs = openTabURLs
        self.activeDocumentURL = activeDocumentURL
        self.layout = layout
    }

    // MARK: - Codable (backward-compatible decode)

    private enum CodingKeys: String, CodingKey {
        case id
        case workspaceDirectoryURL
        case openTabURLs
        case activeDocumentURL
        case layout
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workspaceDirectoryURL = try? container.decode(URL.self, forKey: .workspaceDirectoryURL)
        openTabURLs = (try? container.decode([URL].self, forKey: .openTabURLs)) ?? []
        activeDocumentURL = try? container.decode(URL.self, forKey: .activeDocumentURL)
        layout = try container.decode(LayoutState.self, forKey: .layout)
    }
}
