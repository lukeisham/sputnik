import Foundation

/// The top-level persisted blob written to `layout.json`.
///
/// `LayoutState` is the root of everything that `FilePersistenceService` serialises to
/// `~/Library/Application Support/Sputnik/layout.json`. It *contains* a `PanelLayout`
/// (which panel lives in which slot and how wide each slot is) plus per-slot visibility,
/// the pinned-terminal visibility flag, the recent-files list, and the multi-tab
/// open-document state.
///
/// **Naming note (ISS-001 resolved):** Earlier guide drafts used the name `PanelLayout`
/// for this persisted root. The resolution is: `LayoutState` is the persisted root blob;
/// `PanelLayout` is its panel-arrangement component. They are different types with a
/// clear containment relationship: `LayoutState` ⊃ `PanelLayout`.
///
/// **Panel toggling (replaces Focus Modes):** individual panels are shown/hidden through
/// `visibility` (per slot) and `terminalVisible` (the pinned bottom strip). There is no
/// preset "focus mode" — each panel is toggled independently from the View menu, and the
/// arrangement is restored verbatim on next launch.
///
/// **Multi-tab persistence (ISS-005):** `openDocumentURLs` records the URLs of all
/// saved (non-untitled) open tabs; `activeDocumentURL` records which was active. Untitled
/// and dirty-unsaved documents are handled by the crash-recovery cache (module 3.7) and
/// are not stored here. On restore, the caller reopens each URL via `InterPanelRouter`.
///
/// **Backward compatibility:** every field added after the original schema decodes with a
/// safe default when absent, so older `layout.json` files are never rejected.
public struct LayoutState: Codable, Sendable {

    /// Which panel occupies each named slot and the proportional size of each slot.
    public var panelLayout: PanelLayout

    /// Whether each `PanelPosition` slot is currently visible.
    public var visibility: [PanelPosition: Bool]

    /// Whether the pinned Terminal strip (module 7) is visible. The Terminal is not a
    /// relocatable `PanelPosition`, so its visibility is tracked separately.
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
        panelLayout: .default,
        visibility: Dictionary(
            uniqueKeysWithValues: PanelPosition.allCases.map { ($0, true) }
        ),
        terminalVisible: true,
        recentFiles: [],
        openDocumentURLs: [],
        activeDocumentURL: nil
    )

    // MARK: - Init

    public init(
        panelLayout: PanelLayout,
        visibility: [PanelPosition: Bool],
        terminalVisible: Bool,
        recentFiles: [URL],
        openDocumentURLs: [URL],
        activeDocumentURL: URL?
    ) {
        self.panelLayout = panelLayout
        self.visibility = visibility
        self.terminalVisible = terminalVisible
        self.recentFiles = recentFiles
        self.openDocumentURLs = openDocumentURLs
        self.activeDocumentURL = activeDocumentURL
    }

    // MARK: - Codable (backward-compatible decode)

    private enum CodingKeys: String, CodingKey {
        case panelLayout
        case visibility
        case terminalVisible
        case recentFiles
        case openDocumentURLs
        case activeDocumentURL
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        panelLayout       = try container.decode(PanelLayout.self, forKey: .panelLayout)
        visibility        = try container.decode([PanelPosition: Bool].self, forKey: .visibility)
        // Fields added after the original schema decode with safe defaults when absent.
        terminalVisible   = (try? container.decode(Bool.self, forKey: .terminalVisible)) ?? true
        recentFiles       = (try? container.decode([URL].self, forKey: .recentFiles)) ?? []
        openDocumentURLs  = (try? container.decode([URL].self, forKey: .openDocumentURLs)) ?? []
        activeDocumentURL = try? container.decode(URL.self, forKey: .activeDocumentURL)
    }
}
