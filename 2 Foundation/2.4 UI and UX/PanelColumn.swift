import CoreGraphics
import Foundation

/// A single column in the dynamic panel layout.
///
/// Each column has a stable identity (`id`) assigned at creation, a `renderMode`
/// describing what it currently shows, an optional `originalRenderMode` to support
/// transient toggling (e.g. a `.textEditor` column temporarily shown as
/// `.markdownPreview`), and list of document tab IDs.
///
/// **Threading:** `Sendable` by value — copied across concurrency boundaries.
public struct PanelColumn: Codable, Sendable, Equatable, Identifiable {

    /// Stable identity for SwiftUI `ForEach` and `WindowState.activeColumnID`.
    /// Assigned once at creation; never reassigned.
    public let id: UUID

    /// What this column renders. Multiple columns may share the same renderMode.
    /// `.fileTree` is the sole exception: only one fileTree column is permitted,
    /// always at index 0 or last.
    public var renderMode: PanelID

    /// Non-nil when `renderMode` has been toggled away from the column's creation mode
    /// (e.g. a `.textEditor` column temporarily shown as `.markdownPreview`).
    /// Cleared when toggled back. Codable so toggled state survives relaunch.
    public var originalRenderMode: PanelID?

    /// IDs of the DocumentSessions shown as tabs in this column.
    public var documentIDs: [UUID]

    /// Index into `documentIDs` selecting the visible document.
    public var activeDocumentIndex: Int

    /// Proportional width (0…1). Clamped on use.
    public var width: CGFloat

    /// The DocumentSession ID currently shown, or nil if no document is assigned.
    public var activeDocumentID: UUID? {
        guard !documentIDs.isEmpty,
            activeDocumentIndex < documentIDs.count
        else { return nil }
        return documentIDs[activeDocumentIndex]
    }

    public init(renderMode: PanelID, documentID: UUID? = nil, width: CGFloat = 0.33) {
        self.id = UUID()
        self.renderMode = renderMode
        self.originalRenderMode = nil
        self.documentIDs = documentID.map { [$0] } ?? []
        self.activeDocumentIndex = 0
        self.width = width
    }
}
