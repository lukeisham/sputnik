import Foundation

/// The top-level persisted blob written to `layout.json`.
///
/// `LayoutState` is the root of everything that `FilePersistenceService` serialises to
/// `~/Library/Application Support/Sputnik/layout.json`. It *contains* a `PanelLayout`
/// (which panel lives in which slot and how wide each slot is) plus visibility, focus,
/// and the multi-tab open-document state.
///
/// **Naming note (ISS-001 resolved):** Earlier guide drafts used the name `PanelLayout`
/// for this persisted root. The resolution is: `LayoutState` is the persisted root blob;
/// `PanelLayout` is its panel-arrangement component. They are different types with a
/// clear containment relationship: `LayoutState` ⊃ `PanelLayout`.
///
/// **Multi-tab persistence (ISS-005):** `openDocumentURLs` records the URLs of all
/// saved (non-untitled) open tabs; `activeDocumentURL` records which was active. Untitled
/// and dirty-unsaved documents are handled by the crash-recovery cache (module 3.7) and
/// are not stored here. On restore, the caller reopens each URL via `InterPanelRouter`.
///
/// **Backward compatibility:** `openDocumentURLs` and `activeDocumentURL` default to
/// their empty/nil values when loading a `layout.json` that pre-dates this schema,
/// so older files are never rejected.
public struct LayoutState: Codable, Sendable {

    /// Which panel occupies each named slot and the proportional size of each slot.
    public var panelLayout: PanelLayout

    /// Whether each `PanelPosition` is currently visible.
    public var visibility: [PanelPosition: Bool]

    /// The active focus mode.
    public var focusMode: FocusMode

    /// URLs of all saved open tabs, in their left-to-right tab order.
    /// Untitled documents are excluded; they are re-surfaced via crash recovery.
    public var openDocumentURLs: [URL]

    /// The URL of the tab that was active when the app last quit, or `nil` if
    /// the active tab was untitled.
    public var activeDocumentURL: URL?

    // MARK: - Default

    /// The default state used when `layout.json` is absent, unreadable, or from an
    /// older schema version that predates the multi-tab model.
    public static let `default` = LayoutState(
        panelLayout: .default,
        visibility: Dictionary(
            uniqueKeysWithValues: PanelPosition.allCases.map { ($0, true) }
        ),
        focusMode: .dev,
        openDocumentURLs: [],
        activeDocumentURL: nil
    )

    // MARK: - Init

    public init(
        panelLayout: PanelLayout,
        visibility: [PanelPosition: Bool],
        focusMode: FocusMode,
        openDocumentURLs: [URL],
        activeDocumentURL: URL?
    ) {
        self.panelLayout = panelLayout
        self.visibility = visibility
        self.focusMode = focusMode
        self.openDocumentURLs = openDocumentURLs
        self.activeDocumentURL = activeDocumentURL
    }

    // MARK: - Codable (backward-compatible decode)

    private enum CodingKeys: String, CodingKey {
        case panelLayout
        case visibility
        case focusMode
        case openDocumentURLs
        case activeDocumentURL
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        panelLayout       = try container.decode(PanelLayout.self, forKey: .panelLayout)
        visibility        = try container.decode([PanelPosition: Bool].self, forKey: .visibility)
        focusMode         = try container.decode(FocusMode.self, forKey: .focusMode)
        // Provide defaults for fields added in the multi-tab schema update (ISS-005).
        openDocumentURLs  = (try? container.decode([URL].self, forKey: .openDocumentURLs)) ?? []
        activeDocumentURL = try? container.decode(URL.self, forKey: .activeDocumentURL)
    }
}
