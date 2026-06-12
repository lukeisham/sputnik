import Foundation

/// The top-level persisted blob written to `layout.json`.
///
/// `LayoutState` is the root of everything that `FilePersistenceService` serialises to
/// `~/Library/Application Support/Sputnik/layout.json`. It contains a `DynamicPanelLayout`
/// (which columns exist, their render modes, widths, and open documents) plus the
/// pinned-terminal visibility flag, the recent-files list, and the multi-tab
/// open-document state.
///
/// **Dynamic panels (replaces old fixed-slot model):** the old `PanelLayout` + `visibility`
/// dictionary have been replaced by `dynamicLayout: DynamicPanelLayout`. A panel (column)
/// is visible simply by appearing in `dynamicLayout.columns` — there is no separate
/// visibility toggle per slot.
///
/// **Multi-tab persistence (ISS-005):** `openDocumentURLs` records the URLs of all
/// saved (non-untitled) open tabs; `activeDocumentURL` records which was active. Untitled
/// and dirty-unsaved documents are handled by the crash-recovery cache (module 3.7) and
/// are not stored here. On restore, the caller reopens each URL via `InterPanelRouter`.
///
/// **Backward compatibility:** `dynamicLayout` decodes with a safe default when the key is
/// absent (old schema), so older `layout.json` files are never rejected.
public struct LayoutState: Codable, Sendable {

    /// The ordered list of columns that make up the window's panel arrangement.
    public var dynamicLayout: DynamicPanelLayout

    /// Whether the pinned Terminal strip (module 7) is visible. The Terminal is not a
    /// column in `dynamicLayout`, so its visibility is tracked separately.
    public var terminalVisible: Bool

    /// Most-recently-opened file URLs, newest first, for the File ▸ Open Recent menu.
    /// Capped to `maxRecentFiles` entries by `AppState`.
    public var recentFiles: [URL]

    /// URLs of all saved open tabs, in their left-to-right tab order.
    /// Untitled documents are excluded; they are re-surfaced via crash recovery.
    public var openDocumentURLs: [URL]

    /// The URL of the tab that was active when the app last quit, or `nil` if
    /// the active tab was untitled.
    public var activeDocumentURL: URL?

    /// The maximum number of entries retained in `recentFiles`.
    public static let maxRecentFiles = 10

    // MARK: - Default

    /// The default state used when `layout.json` is absent, unreadable, or from an
    /// older schema version.
    public static let `default` = LayoutState(
        dynamicLayout: .default,
        terminalVisible: true,
        recentFiles: [],
        openDocumentURLs: [],
        activeDocumentURL: nil
    )

    // MARK: - Init

    public init(
        dynamicLayout: DynamicPanelLayout,
        terminalVisible: Bool,
        recentFiles: [URL],
        openDocumentURLs: [URL],
        activeDocumentURL: URL?
    ) {
        self.dynamicLayout = dynamicLayout
        self.terminalVisible = terminalVisible
        self.recentFiles = recentFiles
        self.openDocumentURLs = openDocumentURLs
        self.activeDocumentURL = activeDocumentURL
    }

    // MARK: - Codable (backward-compatible decode)

    private enum CodingKeys: String, CodingKey {
        case dynamicLayout
        case terminalVisible
        case recentFiles
        case openDocumentURLs
        case activeDocumentURL
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // dynamicLayout falls back to .default when the key is absent (old schema).
        dynamicLayout =
            (try? container.decode(DynamicPanelLayout.self, forKey: .dynamicLayout)) ?? .default
        // Fields added after the original schema decode with safe defaults when absent.
        terminalVisible = (try? container.decode(Bool.self, forKey: .terminalVisible)) ?? true
        recentFiles = (try? container.decode([URL].self, forKey: .recentFiles)) ?? []
        openDocumentURLs = (try? container.decode([URL].self, forKey: .openDocumentURLs)) ?? []
        activeDocumentURL = try? container.decode(URL.self, forKey: .activeDocumentURL)
    }
}
