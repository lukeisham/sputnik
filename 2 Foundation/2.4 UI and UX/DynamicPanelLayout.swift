import CoreGraphics
import Foundation

/// The ordered list of columns that make up a window's panel arrangement.
///
/// Replaces the old fixed-slot `PanelLayout` + visibility dictionary model.
/// In the dynamic model, a panel (column) is visible simply by being present
/// in `columns`. There are no "hidden" panels — the user manages which columns
/// exist through add / remove / move operations.
///
/// **Invariants:**
/// - `columns` is never empty. Removing the last column restores `.default`.
/// - At most one `.fileTree` column, always at index 0 or last.
public struct DynamicPanelLayout: Codable, Sendable, Equatable {

    /// Ordered columns, left to right. Always at least one column.
    public var columns: [PanelColumn]

    /// The default three-column layout: File Tree | Text Editor | Markdown Preview.
    public static let `default` = DynamicPanelLayout(columns: [
        PanelColumn(renderMode: .fileTree, width: 0.20),
        PanelColumn(renderMode: .textEditor, width: 0.45),
        PanelColumn(renderMode: .markdownPreview, width: 0.35),
    ])

    public init(columns: [PanelColumn]) {
        precondition(!columns.isEmpty, "DynamicPanelLayout requires at least one column")
        self.columns = columns
    }

    // MARK: - Column role

    public enum ColumnRole: Equatable {
        /// Focused column — full editing + help-context.
        case active
        /// Preview showing the same document as the active text editor — help-context only.
        case activePair
        /// All others — copy + rename only.
        case viewOnly
    }

    /// Active pair rule: a column is `.activePair` if and only if:
    ///   1. Its renderMode is `.markdownPreview` or `.htmlPreview`
    ///   2. Its `activeDocumentID` matches the active column's `activeDocumentID`
    ///   3. The active column's renderMode is `.textEditor`
    public func role(of columnID: UUID, activeColumnID: UUID?) -> ColumnRole {
        guard let activeID = activeColumnID else { return .viewOnly }
        if columnID == activeID { return .active }
        guard let activeCol = columns.first(where: { $0.id == activeID }),
            activeCol.renderMode == .textEditor,
            let thisCol = columns.first(where: { $0.id == columnID }),
            thisCol.renderMode == .markdownPreview || thisCol.renderMode == .htmlPreview,
            let thisDoc = thisCol.activeDocumentID,
            thisDoc == activeCol.activeDocumentID
        else { return .viewOnly }
        return .activePair
    }

    // MARK: - Constraint helpers

    /// `.fileTree`: only one allowed, only at index 0 or last.
    /// All other modes: always insertable.
    public func canInsert(renderMode: PanelID, at index: Int) -> Bool {
        if renderMode == .fileTree {
            let alreadyHasFileTree = columns.contains { $0.renderMode == .fileTree }
            let isEdge = (index == 0 || index == columns.count)
            return !alreadyHasFileTree && isEdge
        }
        return true
    }

    // MARK: - Render-mode toggle

    /// Switch a view-only text-sourced column between `.textEditor`, `.markdownPreview`,
    /// and `.htmlPreview`. Guards silently if the column is not text-sourced.
    /// Caller must verify file extension supports newMode before calling.
    public mutating func toggleRenderMode(ofColumnID columnID: UUID, to newMode: PanelID) {
        guard let i = columns.firstIndex(where: { $0.id == columnID }) else { return }
        let isTextSourced =
            columns[i].renderMode == .textEditor
            || columns[i].originalRenderMode == .textEditor
        guard isTextSourced else { return }
        guard newMode == .textEditor || newMode == .markdownPreview || newMode == .htmlPreview
        else { return }
        if newMode == .textEditor {
            columns[i].renderMode = .textEditor
            columns[i].originalRenderMode = nil
        } else {
            if columns[i].originalRenderMode == nil {
                columns[i].originalRenderMode = columns[i].renderMode
            }
            columns[i].renderMode = newMode
        }
    }

    /// Revert a toggled column to `.textEditor`. Called when the column is focused
    /// (tapped) so the user goes straight into editing mode.
    public mutating func revertToggleIfNeeded(forColumnID columnID: UUID) {
        guard let i = columns.firstIndex(where: { $0.id == columnID }) else { return }
        if columns[i].originalRenderMode == .textEditor {
            columns[i].renderMode = .textEditor
            columns[i].originalRenderMode = nil
        }
    }

    // MARK: - Column mutations (called @MainActor from ContentView)

    /// Insert a new column at the given index.
    public mutating func addColumn(renderMode: PanelID, documentID: UUID? = nil, at index: Int) {
        guard canInsert(renderMode: renderMode, at: index) else { return }
        let col = PanelColumn(renderMode: renderMode, documentID: documentID)
        columns.insert(col, at: min(index, columns.count))
        normaliseWidths()
    }

    /// Move a column to a new position.
    public mutating func moveColumn(id columnID: UUID, to destinationIndex: Int) {
        guard let from = columns.firstIndex(where: { $0.id == columnID }) else { return }
        if columns[from].renderMode == .fileTree {
            let isEdge = (destinationIndex == 0 || destinationIndex == columns.count - 1)
            guard isEdge else { return }
        }
        let col = columns.remove(at: from)
        columns.insert(col, at: min(destinationIndex, columns.count))
        normaliseWidths()
    }

    /// Add a document tab to the specified column.
    public mutating func addDocument(_ documentID: UUID, toColumnWithID columnID: UUID) {
        guard let i = columns.firstIndex(where: { $0.id == columnID }) else { return }
        guard !columns[i].documentIDs.contains(documentID) else { return }
        columns[i].documentIDs.append(documentID)
    }

    /// Remove a document tab from the specified column.
    public mutating func removeDocument(_ documentID: UUID, fromColumnWithID columnID: UUID) {
        guard let i = columns.firstIndex(where: { $0.id == columnID }) else { return }
        columns[i].documentIDs.removeAll { $0 == documentID }
        if columns[i].activeDocumentIndex >= columns[i].documentIDs.count {
            columns[i].activeDocumentIndex = max(0, columns[i].documentIDs.count - 1)
        }
        removeEmptyColumns()
    }

    /// Remove a column by ID. Restores `.default` if removing it would leave `columns` empty.
    public mutating func removeColumn(id columnID: UUID) {
        columns.removeAll { $0.id == columnID }
        if columns.isEmpty { columns = DynamicPanelLayout.default.columns }
    }

    /// Move the active text editor column to sit immediately beside the File Tree.
    /// No-op if already adjacent, or if there is no File Tree.
    public mutating func moveActiveEditorAdjacentToFileTree(activeColumnID: UUID) {
        guard let ftIndex = columns.firstIndex(where: { $0.renderMode == .fileTree }),
            let teIndex = columns.firstIndex(where: { $0.id == activeColumnID }),
            columns[teIndex].renderMode == .textEditor
        else { return }
        guard abs(teIndex - ftIndex) != 1 else { return }
        let targetIndex = (ftIndex == 0) ? 1 : columns.count - 2
        guard targetIndex >= 0, targetIndex < columns.count, targetIndex != teIndex else { return }
        let col = columns.remove(at: teIndex)
        columns.insert(col, at: min(targetIndex, columns.count))
        normaliseWidths()
    }

    // MARK: - Private

    /// Remove columns that have no documents, unless they are the file tree.
    private mutating func removeEmptyColumns() {
        columns.removeAll { $0.renderMode != .fileTree && $0.documentIDs.isEmpty }
        if columns.isEmpty { columns = DynamicPanelLayout.default.columns }
    }

    /// Spread total width evenly across all columns.
    private mutating func normaliseWidths() {
        guard !columns.isEmpty else { return }
        let even = 1.0 / CGFloat(columns.count)
        for i in columns.indices { columns[i].width = even }
    }
}
