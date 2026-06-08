import Foundation

/// The top-level persisted blob written to `layout.json`.
///
/// `LayoutState` is the root of everything that `FilePersistenceService` serialises to
/// `~/Library/Application Support/Sputnik/layout.json`. It *contains* a `PanelLayout`
/// (which panel lives in which slot and how wide each slot is) plus visibility, focus,
/// and the last-opened file.
///
/// **Naming note (ISS-001 resolved):** Earlier guide drafts used the name `PanelLayout`
/// for this persisted root. The resolution is: `LayoutState` is the persisted root blob;
/// `PanelLayout` is its panel-arrangement component. They are different types with a
/// clear containment relationship: `LayoutState` ⊃ `PanelLayout`.
public struct LayoutState: Codable, Sendable {

    /// Which panel occupies each named slot and the proportional size of each slot.
    public var panelLayout: PanelLayout

    /// Whether each `PanelPosition` is currently visible.
    public var visibility: [PanelPosition: Bool]

    /// The active focus mode.
    public var focusMode: FocusMode

    /// The URL of the file that was open when the app last quit (restored on relaunch).
    public var lastOpenFile: URL?

    /// The default state used when `layout.json` is absent or unreadable.
    public static let `default` = LayoutState(
        panelLayout: .default,
        visibility: Dictionary(
            uniqueKeysWithValues: PanelPosition.allCases.map { ($0, true) }
        ),
        focusMode: .dev,
        lastOpenFile: nil
    )

    public init(
        panelLayout: PanelLayout,
        visibility: [PanelPosition: Bool],
        focusMode: FocusMode,
        lastOpenFile: URL?
    ) {
        self.panelLayout = panelLayout
        self.visibility = visibility
        self.focusMode = focusMode
        self.lastOpenFile = lastOpenFile
    }
}
