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
/// - After every mutation, `columns.map(\.width).reduce(0, +)` ≈ 1.0.
public struct DynamicPanelLayout: Codable, Sendable, Equatable {

    /// Minimum proportional width a column can shrink to during resize.
    /// 0.08 ensures even the narrowest column stays usable (~96 pt at 1200 pt window).
    public static let minColumnWidthProportion: CGFloat = 0.08

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

    // MARK: - Resize mutation

    /// Shifts width between the two adjacent columns at `leftIndex` and `leftIndex + 1`
    /// by `delta` points (converted to a proportional shift using `totalAvailableWidth`).
    /// Both neighbours are clamped to `minColumnWidthProportion`; their summed width is conserved.
    public mutating func resize(
        betweenLeftIndex leftIndex: Int,
        delta: CGFloat,
        totalAvailableWidth: CGFloat,
        minWidthProportion: CGFloat = DynamicPanelLayout.minColumnWidthProportion
    ) {
        guard leftIndex >= 0, leftIndex + 1 < columns.count, totalAvailableWidth > 0 else { return }
        let deltaNorm = delta / totalAvailableWidth
        let sum = columns[leftIndex].width + columns[leftIndex + 1].width
        var newLeft = columns[leftIndex].width + deltaNorm
        var newRight = columns[leftIndex + 1].width - deltaNorm
        // Clamp both neighbours to the minimum proportion.
        if newLeft < minWidthProportion {
            newLeft = minWidthProportion
            newRight = sum - minWidthProportion
        }
        if newRight < minWidthProportion {
            newRight = minWidthProportion
            newLeft = sum - minWidthProportion
        }
        columns[leftIndex].width = newLeft
        columns[leftIndex + 1].width = newRight
    }

    /// Checks whether the two columns at `leftIndex` and `leftIndex + 1` are within
    /// a small tolerance of an even split. Returns `true` when the left column's width
    /// is within `tolerance` of half the summed width.
    public func isNearEvenSplit(leftIndex: Int, tolerance: CGFloat = 0.02) -> Bool {
        guard leftIndex >= 0, leftIndex + 1 < columns.count else { return false }
        let sum = columns[leftIndex].width + columns[leftIndex + 1].width
        guard sum > 0 else { return false }
        return abs(columns[leftIndex].width - sum / 2) < tolerance
    }

    /// Snap the two columns at `leftIndex` and `leftIndex + 1` to an exact even split.
    public mutating func snapToEvenSplit(leftIndex: Int) {
        guard leftIndex >= 0, leftIndex + 1 < columns.count else { return }
        let sum = columns[leftIndex].width + columns[leftIndex + 1].width
        columns[leftIndex].width = sum / 2
        columns[leftIndex + 1].width = sum / 2
    }

    /// Explicit reset of all column widths to an even split.
    /// Never called automatically — only via the user-visible "Restore Default Layout" command.
    public mutating func resetToEvenWidths() {
        guard !columns.isEmpty else { return }
        let even = 1.0 / CGFloat(columns.count)
        for i in columns.indices { columns[i].width = even }
    }

    // MARK: - Column mutations (called @MainActor from ContentView)

    /// Insert a new column at the given index. Existing columns are shrunk
    /// proportionally to make room for the new column's default share.
    public mutating func addColumn(renderMode: PanelID, documentID: UUID? = nil, at index: Int) {
        guard canInsert(renderMode: renderMode, at: index) else { return }
        let col = PanelColumn(renderMode: renderMode, documentID: documentID)
        columns.insert(col, at: min(index, columns.count))
        rescaleWidthsProportionallyForInsertion(at: min(index, columns.count - 1))
    }

    /// Move a column to a new position. Widths are preserved — no rescaling needed
    /// since the column count does not change.
    public mutating func moveColumn(id columnID: UUID, to destinationIndex: Int) {
        guard let from = columns.firstIndex(where: { $0.id == columnID }) else { return }
        if columns[from].renderMode == .fileTree {
            let isEdge = (destinationIndex == 0 || destinationIndex == columns.count - 1)
            guard isEdge else { return }
        }
        let col = columns.remove(at: from)
        columns.insert(col, at: min(destinationIndex, columns.count))
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
    /// Widths are preserved — no rescaling needed (column count unchanged).
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
    }

    // MARK: - Private

    /// Remove columns that have no documents, unless they are the file tree.
    /// Freed width is redistributed proportionally to remaining columns.
    private mutating func removeEmptyColumns() {
        let beforeCount = columns.count
        columns.removeAll { $0.renderMode != .fileTree && $0.documentIDs.isEmpty }
        if columns.isEmpty {
            columns = DynamicPanelLayout.default.columns
        } else if columns.count < beforeCount {
            rescaleWidthsProportionallyForRemoval()
        }
    }

    /// Rescale widths proportionally after inserting a new column.
    /// The new column gets a default share; existing columns shrink pro-rata.
    private mutating func rescaleWidthsProportionallyForInsertion(at insertedIndex: Int) {
        let n = CGFloat(columns.count)
        let newShare = 1.0 / n
        let scaleFactor = 1.0 - newShare  // remaining share for existing columns
        for i in columns.indices where i != insertedIndex {
            columns[i].width *= scaleFactor
        }
        columns[insertedIndex].width = newShare
    }

    /// Rescale widths proportionally after removing a column.
    /// Remaining columns absorb the freed share pro-rata so the sum stays 1.0.
    private mutating func rescaleWidthsProportionallyForRemoval() {
        let totalWidth = columns.reduce(0) { $0 + $1.width }
        guard totalWidth > 0 else {
            resetToEvenWidths()
            return
        }
        let scaleFactor = 1.0 / totalWidth
        for i in columns.indices {
            columns[i].width *= scaleFactor
        }
    }
}
