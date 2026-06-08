import Foundation

/// The named layout slots into which relocatable panels can be placed.
public enum PanelPosition: String, Codable, Sendable, CaseIterable, Hashable {
    /// Left column.
    case left
    /// Upper centre area.
    case centerUpper
    /// Lower centre area (hidden unless a panel requires it, e.g. PDF Viewer).
    case centerLower
    /// Right column.
    case right
}
