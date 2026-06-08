import CoreGraphics
import Foundation

/// The panel-arrangement component of `LayoutState`.
///
/// `PanelLayout` captures *which* panel occupies each named slot and the proportional
/// width/height of each slot. It is a component type — it is always owned by and
/// serialised through `LayoutState` (see `2 Foundation/2.5 Persistence/LayoutState.swift`),
/// never persisted standalone.
public struct PanelLayout: Codable, Sendable, Equatable {

    /// Maps each slot to the panel currently assigned to it.
    ///
    /// Slots absent from the map fall back to the default assignment at load time
    /// so old layout files remain compatible when new panels are added.
    public var assignments: [PanelPosition: PanelID]

    /// The proportional size (0…1) of each slot within its split container.
    ///
    /// Values outside 0…1 are clamped to safe bounds when applied to the view.
    public var sizes: [PanelPosition: CGFloat]

    /// The default layout: File Tree left, Text Editor centre-upper, empty right, PDF lower-centre.
    public static let `default` = PanelLayout(
        assignments: [
            .left:        .fileTree,
            .centerUpper: .textEditor,
            .right:       .markdownPreview,
            .centerLower: .pdfViewer
        ],
        sizes: [
            .left:        0.20,
            .centerUpper: 0.55,
            .right:       0.25,
            .centerLower: 0.40
        ]
    )

    public init(assignments: [PanelPosition: PanelID], sizes: [PanelPosition: CGFloat]) {
        self.assignments = assignments
        self.sizes = sizes
    }
}
