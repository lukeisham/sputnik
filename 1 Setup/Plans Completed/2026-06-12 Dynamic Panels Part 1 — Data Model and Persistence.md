---
plan: Dynamic Panels — Part 1 of 3: Data Model and Persistence
module: 2 Foundation (2.4 UI and UX, 2.5 Persistence)
created: 2026-06-12
status: pending
depends_on: none
unlocks: "Part 2 — UI Shell"
related_issues: none
---

## Purpose
Define and persist the new dynamic column data model. Nothing visible changes — the old layout types (`PanelPosition`, `PanelLayout`) remain untouched until Part 3. This plan is purely additive: new files are created, existing ones are lightly updated.

## Success Condition
- `PanelColumn` and `DynamicPanelLayout` exist in `2 Foundation/2.4 UI and UX/` and compile with zero errors.
- `LayoutState` persists `dynamicLayout: DynamicPanelLayout` and falls back to `.default` when the key is absent (old schema forward-compat).
- `WindowState` exposes `activeColumnID: UUID?` and the two computed properties.
- A manual round-trip encode/decode of `LayoutState.default` succeeds.
- All existing functionality still works (app launches, old layout still renders — the old types are still present).

---

## Step 1 — Add `displayBadge` to `PanelID`

File: `2 Foundation/2.4 UI and UX/PanelID.swift`

Add a computed property to the existing `PanelID` enum:

```swift
public var displayBadge: String? {
    switch self {
    case .textEditor:       return "TXT"
    case .markdownPreview:  return "MD"
    case .htmlPreview:      return "HTML"
    case .pdfViewer:        return "PDF"
    case .fileTree:         return nil
    case .asciiArtHelp, .markdownHelp, .htmlHelp, .grammarHelp: return nil
    }
}
```

Note: when a PDF Viewer column is showing an image file, `PanelColumnView` (Part 2) overrides this with `"PNG"` — no change needed here.

---

## Step 2 — Create `PanelColumn.swift`

New file: `2 Foundation/2.4 UI and UX/PanelColumn.swift`

```swift
public struct PanelColumn: Codable, Sendable, Equatable, Identifiable {
    /// Stable identity for SwiftUI ForEach and WindowState.activeColumnID.
    /// Assigned once at creation; never reassigned.
    public let id: UUID

    /// What this column renders. Multiple columns may share the same renderMode.
    /// .fileTree is the sole exception: only one fileTree column is permitted,
    /// always at index 0 or last.
    public var renderMode: PanelID

    /// Non-nil when renderMode has been toggled away from the column's creation mode
    /// (e.g. a .textEditor column temporarily shown as .markdownPreview).
    /// Cleared when toggled back. Codable so toggled state survives relaunch.
    public var originalRenderMode: PanelID?

    /// IDs of the DocumentSessions shown as tabs in this column.
    public var documentIDs: [UUID]

    /// Index into documentIDs selecting the visible document.
    public var activeDocumentIndex: Int

    /// Proportional width (0…1). Clamped on use.
    public var width: CGFloat

    /// The DocumentSession ID currently shown, or nil if no document is assigned.
    public var activeDocumentID: UUID? {
        guard !documentIDs.isEmpty,
              activeDocumentIndex < documentIDs.count else { return nil }
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
```

---

## Step 3 — Create `DynamicPanelLayout.swift`

New file: `2 Foundation/2.4 UI and UX/DynamicPanelLayout.swift`

```swift
public struct DynamicPanelLayout: Codable, Sendable, Equatable {

    /// Ordered columns, left to right. Always at least one column.
    public var columns: [PanelColumn]

    public static let `default` = DynamicPanelLayout(columns: [
        PanelColumn(renderMode: .fileTree,        width: 0.20),
        PanelColumn(renderMode: .textEditor,      width: 0.45),
        PanelColumn(renderMode: .markdownPreview, width: 0.35),
    ])

    public init(columns: [PanelColumn]) {
        precondition(!columns.isEmpty)
        self.columns = columns
    }

    // MARK: - Column role

    public enum ColumnRole: Equatable {
        case active      // focused column — full editing + help-context
        case activePair  // preview showing same doc as active text editor — help-context only
        case viewOnly    // all others — copy + rename only
    }

    /// Active pair rule: a column is .activePair if and only if:
    ///   1. Its renderMode is .markdownPreview or .htmlPreview
    ///   2. Its activeDocumentID matches the active column's activeDocumentID
    ///   3. The active column's renderMode is .textEditor
    public func role(of columnID: UUID, activeColumnID: UUID?) -> ColumnRole {
        guard let activeID = activeColumnID else { return .viewOnly }
        if columnID == activeID { return .active }
        guard let activeCol = columns.first(where: { $0.id == activeID }),
              activeCol.renderMode == .textEditor,
              let thisCol = columns.first(where: { $0.id == columnID }),
              (thisCol.renderMode == .markdownPreview || thisCol.renderMode == .htmlPreview),
              let thisDoc = thisCol.activeDocumentID,
              thisDoc == activeCol.activeDocumentID
        else { return .viewOnly }
        return .activePair
    }

    // MARK: - Constraint helpers

    /// .fileTree: only one allowed, only at index 0 or last.
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

    /// Switch a view-only text-sourced column between .textEditor, .markdownPreview,
    /// and .htmlPreview. Guards silently if the column is not text-sourced.
    /// Caller must verify file extension supports newMode before calling.
    public mutating func toggleRenderMode(ofColumnID columnID: UUID, to newMode: PanelID) {
        guard let i = columns.firstIndex(where: { $0.id == columnID }) else { return }
        let isTextSourced = columns[i].renderMode == .textEditor
                         || columns[i].originalRenderMode == .textEditor
        guard isTextSourced else { return }
        guard newMode == .textEditor || newMode == .markdownPreview || newMode == .htmlPreview else { return }
        if newMode == .textEditor {
            columns[i].renderMode = .textEditor
            columns[i].originalRenderMode = nil
        } else {
            if columns[i].originalRenderMode == nil {
                columns[i].originalRenderMode = .textEditor
            }
            columns[i].renderMode = newMode
        }
    }

    /// Revert a toggled column to .textEditor. Called when the column is focused
    /// (tapped) so the user goes straight into editing mode.
    public mutating func revertToggleIfNeeded(forColumnID columnID: UUID) {
        guard let i = columns.firstIndex(where: { $0.id == columnID }) else { return }
        if columns[i].originalRenderMode == .textEditor {
            columns[i].renderMode = .textEditor
            columns[i].originalRenderMode = nil
        }
    }

    // MARK: - Column mutations (called @MainActor from ContentView)

    public mutating func addColumn(renderMode: PanelID, documentID: UUID? = nil, at index: Int) {
        guard canInsert(renderMode: renderMode, at: index) else { return }
        let col = PanelColumn(renderMode: renderMode, documentID: documentID)
        columns.insert(col, at: min(index, columns.count))
        normaliseWidths()
    }

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

    public mutating func addDocument(_ documentID: UUID, toColumnWithID columnID: UUID) {
        guard let i = columns.firstIndex(where: { $0.id == columnID }) else { return }
        guard !columns[i].documentIDs.contains(documentID) else { return }
        columns[i].documentIDs.append(documentID)
    }

    public mutating func removeDocument(_ documentID: UUID, fromColumnWithID columnID: UUID) {
        guard let i = columns.firstIndex(where: { $0.id == columnID }) else { return }
        columns[i].documentIDs.removeAll { $0 == documentID }
        if columns[i].activeDocumentIndex >= columns[i].documentIDs.count {
            columns[i].activeDocumentIndex = max(0, columns[i].documentIDs.count - 1)
        }
        removeEmptyColumns()
    }

    public mutating func removeColumn(id columnID: UUID) {
        columns.removeAll { $0.id == columnID }
        if columns.isEmpty { columns = DynamicPanelLayout.default.columns }
    }

    /// Move the active text editor column to sit immediately beside the File Tree.
    /// No-op if already adjacent, or if there is no File Tree.
    public mutating func moveActiveEditorAdjacentToFileTree(activeColumnID: UUID) {
        guard let ftIndex = columns.firstIndex(where: { $0.renderMode == .fileTree }),
              let teIndex = columns.firstIndex(where: { $0.id == activeColumnID }),
              columns[teIndex].renderMode == .textEditor else { return }
        guard abs(teIndex - ftIndex) != 1 else { return }
        let targetIndex = (ftIndex == 0) ? 1 : columns.count - 2
        guard targetIndex >= 0, targetIndex < columns.count, targetIndex != teIndex else { return }
        let col = columns.remove(at: teIndex)
        columns.insert(col, at: min(targetIndex, columns.count))
        normaliseWidths()
    }

    // MARK: - Private

    private mutating func removeEmptyColumns() {
        columns.removeAll { $0.renderMode != .fileTree && $0.documentIDs.isEmpty }
        if columns.isEmpty { columns = DynamicPanelLayout.default.columns }
    }

    private mutating func normaliseWidths() {
        guard !columns.isEmpty else { return }
        let even = 1.0 / CGFloat(columns.count)
        for i in columns.indices { columns[i].width = even }
    }
}
```

---

## Step 4 — Update `LayoutState.swift`

File: `2 Foundation/2.5 Persistence/LayoutState.swift`

- Replace `panelLayout: PanelLayout` with `dynamicLayout: DynamicPanelLayout`.
- Remove `visibility: [PanelPosition: Bool]` entirely — visibility is now implicit (a panel is visible if it appears in `dynamicLayout.columns`).
- Keep `terminalVisible: Bool`, `recentFiles`, `openDocumentURLs`, `activeDocumentURL` unchanged.
- Update `CodingKeys`, `init`, and `init(from decoder:)`.
- Update `LayoutState.default` to use `DynamicPanelLayout.default`.
- Decode fallback: if `dynamicLayout` key is absent (old schema), fall back to `DynamicPanelLayout.default` — silent replace on first launch with new schema, no crash.

---

## Step 5 — Update `WindowState.swift`

File: `2 Foundation/2.2 Global State Management/WindowState.swift`

- Search for any code reading `layout.panelLayout` or `layout.visibility` and update to `layout.dynamicLayout`.
- Add `var activeColumnID: UUID?` — transient, NOT persisted. Tracks which column has keyboard focus.
- Add computed properties:
  ```swift
  var activeColumnRenderMode: PanelID? {
      layout.dynamicLayout.columns.first(where: { $0.id == activeColumnID })?.renderMode
  }
  /// nil if active column is not .textEditor or has no open document.
  var activeTextEditorDocumentID: UUID? {
      guard activeColumnRenderMode == .textEditor else { return nil }
      return layout.dynamicLayout.columns.first(where: { $0.id == activeColumnID })?.activeDocumentID
  }
  ```
- On launch, initialise `activeColumnID` to `dynamicLayout.columns.first(where: { $0.renderMode == .textEditor })?.id ?? dynamicLayout.columns.first?.id`.

---

## Step 6 — Verify: Foundation compiles and layout round-trips

- Run `swift build` scoped to `FoundationModule`. Zero errors, zero warnings.
- In a debug session or unit test: encode `LayoutState.default` to JSON, decode it back, assert equality.
- Confirm the app still launches (old layout UI still renders — legacy types not yet removed).

---

### ⏸ PAUSE — Checkpoint

> Confirm before handing off to Part 2:
> - `PanelColumn`, `DynamicPanelLayout` present and compile cleanly.
> - `LayoutState` uses `dynamicLayout`; decode fallback works for old schema.
> - `WindowState` has `activeColumnID` and the two computed properties.
> - App still launches with the old UI intact.
> - Zero errors, zero warnings.

---

## Risks and Notes

- `originalRenderMode` must be included in `PanelColumn`'s synthesised `Codable` conformance — it is, since `PanelID` is already `Codable`. Include a toggled column in the round-trip test (Step 6).
- `activeColumnID` is NOT in `layout.json` — it is transient. Never add it to `CodingKeys`.
- Do NOT delete `PanelLayout.swift` or `PanelPosition.swift` yet — that is Part 3 work.
- `removeEmptyColumns` only prunes non-fileTree columns. The fileTree column is never auto-pruned.
- `role(of:)` is a pure function — never cache it or store the result on `PanelColumn`.

## Files Changed

- `2 Foundation/2.4 UI and UX/PanelID.swift` — `displayBadge` added
- `2 Foundation/2.4 UI and UX/PanelColumn.swift` — NEW
- `2 Foundation/2.4 UI and UX/DynamicPanelLayout.swift` — NEW
- `2 Foundation/2.5 Persistence/LayoutState.swift` — `dynamicLayout` replaces `panelLayout` + `visibility`
- `2 Foundation/2.2 Global State Management/WindowState.swift` — `activeColumnID` + computed properties added
