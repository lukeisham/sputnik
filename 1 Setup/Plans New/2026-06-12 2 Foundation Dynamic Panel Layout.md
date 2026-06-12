---
plan: Dynamic Panel Layout
module: 2 Foundation (2.4 UI and UX, 2.5 Persistence) + App-Sputnik/ContentView
created: 2026-06-12
status: pending
related_issues: none
---

## Purpose
Replace the fixed four-slot panel layout (`.left`, `.centerUpper`, `.centerLower`, `.right`) with a dynamic ordered-column model where panels are draggable via their title bar into any column position and can be tabbed together within a column. Three hard layout invariants apply: (1) the File Tree is always in the leftmost or rightmost column — never in the centre; (2) the Terminal strip is always pinned to the bottom, full-width; (3) the Scratchpad is docked at the bottom-right corner as a fixed panel beside the Terminal — it is no longer a floating overlay. Any combination of the five content panels (File Tree, Text Editor, Markdown Preview, HTML Preview, PDF Viewer) may occupy the remaining columns; no slot is reserved for any specific panel.

## Success Condition
- Panels can be dragged by their title bar and dropped to insert a new column, or dropped on an existing column to become a tab within it.
- **File Tree invariant**: File Tree cannot be dropped anywhere except the leftmost or rightmost column. The drop is rejected with a red-highlight visual cue. On initial launch the File Tree is always in column index 0. If the user moves it to the rightmost position it stays there; it cannot be placed in any centre column under any circumstance.
- **Dynamic occupancy**: No column slot is reserved for any specific panel. If PDF Viewer is not in the layout, its space is simply not allocated — other panels expand to fill it. Any content panel (Text Editor, Markdown Preview, HTML Preview, PDF Viewer) can occupy any non-edge column.
- If a column contains more than one panel, a horizontally scrollable tab bar appears at the top of that column. The user can scroll the tab bar to reveal all tabs and click any tab to bring that panel to the front as the active panel in that column.
- **Column type indicators**: every column title bar and every tab button shows a short type badge (e.g. `MD`, `HTML`, `PDF`, `PNG`, `TXT`) identifying what kind of content it displays. The Text Editor column additionally shows a thin 2 pt coloured border around its entire frame when it is the active editing surface (i.e. there is an open document). All other columns show no border.
- **Terminal**: always full-width, pinned at the bottom. Does not participate in the column system.
- **Scratchpad**: docked at the bottom-right corner as a fixed panel beside the Terminal strip (not a floating overlay). Toggled by ⇧⌘K. Width is user-resizable via a drag handle on its left edge. The scratchpad floating-overlay code (`scratchpadFrame` persistence, drag-to-reposition, edge resize handles) is removed.
- The layout persists across launches. An old `layout.json` using the legacy schema is silently discarded and replaced by the default dynamic layout.
- All legacy types (`PanelPosition`, `PanelLayout`) are deleted. No references to them remain in any file.
- All affected Module Guides (2.0, 2.4, 2.5) are updated.
- The project compiles with zero errors and zero warnings.

---

## Phase 1 — New data model (Foundation only)

> Goal: define the replacement types. Nothing in the app breaks yet — the old types still exist alongside the new ones until Phase 3.

- [ ] **Step 1 — Add `displayBadge` to `PanelID` and create `PanelColumn.swift`**
  What (part A): In `2 Foundation/2.4 UI and UX/PanelID.swift`, add a computed property `displayBadge: String?` to the existing `PanelID` enum:
  ```swift
  /// Short label shown in column title bars and tab buttons to identify content type.
  /// `nil` for panels that are self-evident (File Tree) or handled by a border instead.
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
  Why: Centralising the badge string on `PanelID` means `PanelColumnView` never contains a switch statement over panel types — it just reads `panelID.displayBadge`. Adding image viewer later only requires adding one case here (SR-1, SR-6).

  Note: when the PDF Viewer is showing an image file (`.png`/`.jpg`), the badge should read `PNG` not `PDF`. This requires `PanelColumnView` to inspect the active document's `FileType` when the active panel is `.pdfViewer` and override the badge accordingly — handle this in Step 7.

  What (part B): In `2 Foundation/2.4 UI and UX/`, create `PanelColumn.swift` containing:
  ```swift
  public struct PanelColumn: Codable, Sendable, Equatable, Identifiable {
      /// Stable UUID used by SwiftUI ForEach and by WindowState.activeColumnID.
      /// Assigned once at creation; never reassigned.
      public let id: UUID

      /// What this column renders. Multiple columns may share the same renderMode
      /// (e.g. four textEditor columns each showing a different file).
      /// Exception: .fileTree is unique — only one fileTree column is allowed,
      /// and it must occupy the leftmost or rightmost position.
      public var renderMode: PanelID

      /// IDs of the DocumentSessions shown as tabs in this column.
      /// The session at activeDocumentIndex is the one rendered.
      /// An empty array is valid only transiently (e.g. the last document was closed);
      /// DynamicPanelLayout.removeEmptyColumns() prunes it immediately after.
      public var documentIDs: [UUID]

      /// Index into documentIDs selecting the visible document. Always in
      /// 0..<max(1, documentIDs.count); clamped defensively on read.
      public var activeDocumentIndex: Int

      /// Proportional width of this column in the window (0…1). Clamped on use.
      public var width: CGFloat

      /// The DocumentSession ID currently shown in this column, or nil if no
      /// document has been assigned yet (e.g. a freshly created preview column).
      public var activeDocumentID: UUID? {
          guard !documentIDs.isEmpty,
                activeDocumentIndex < documentIDs.count else { return nil }
          return documentIDs[activeDocumentIndex]
      }

      public init(renderMode: PanelID, documentID: UUID? = nil, width: CGFloat = 0.33) {
          self.id = UUID()
          self.renderMode = renderMode
          self.documentIDs = documentID.map { [$0] } ?? []
          self.activeDocumentIndex = 0
          self.width = width
      }
  }
  ```
  Why: The `UUID id` lets SwiftUI identify columns stably even when multiple columns share the same `renderMode` — without it, a `ForEach` over four `.textEditor` columns would lose state on every reorder. The `documentIDs` array is the per-column tab list: each column independently decides which document(s) it shows, so four text editor columns can each show a different file simultaneously.

- [ ] **Step 2 — Create `DynamicPanelLayout.swift`**
  What: In `2 Foundation/2.4 UI and UX/`, create `DynamicPanelLayout.swift` containing:
  ```swift
  public struct DynamicPanelLayout: Codable, Sendable, Equatable {
      /// Ordered columns, left to right. Must contain at least one column.
      /// Multiple columns may share the same renderMode (e.g. four .textEditor columns,
      /// three .markdownPreview columns). The sole exception is .fileTree: only one
      /// fileTree column is permitted, always at index 0 or last.
      public var columns: [PanelColumn]

      // MARK: - Default
      public static let `default` = DynamicPanelLayout(columns: [
          PanelColumn(renderMode: .fileTree,        width: 0.20),
          PanelColumn(renderMode: .textEditor,      width: 0.45),
          PanelColumn(renderMode: .markdownPreview, width: 0.35),
      ])

      public init(columns: [PanelColumn]) {
          precondition(!columns.isEmpty, "DynamicPanelLayout must have at least one column")
          self.columns = columns
      }

      // MARK: - Column role

      /// The role a column plays given the currently active column and document.
      ///
      /// - active: this is the focused column — full editing and help-context enabled.
      /// - activePair: this column is showing the same document as the active text
      ///   editor column, in a complementary render mode (.markdownPreview or .htmlPreview).
      ///   Help-context is enabled; editing is not.
      /// - viewOnly: all other columns — copy and rename only; no editing, no help-context.
      public enum ColumnRole: Equatable {
          case active
          case activePair
          case viewOnly
      }

      /// Returns the role of the column identified by `columnID`.
      ///
      /// Active pair rule: a column is `.activePair` if and only if:
      ///   1. Its renderMode is .markdownPreview or .htmlPreview, AND
      ///   2. Its activeDocumentID matches the activeDocumentID of the active column, AND
      ///   3. The active column's renderMode is .textEditor.
      public func role(of columnID: UUID, activeColumnID: UUID?) -> ColumnRole {
          guard let activeID = activeColumnID else { return .viewOnly }
          if columnID == activeID { return .active }

          guard let activeCol = columns.first(where: { $0.id == activeID }),
                activeCol.renderMode == .textEditor,
                let thisCol = columns.first(where: { $0.id == columnID }),
                (thisCol.renderMode == .markdownPreview || thisCol.renderMode == .htmlPreview),
                thisCol.activeDocumentID != nil,
                thisCol.activeDocumentID == activeCol.activeDocumentID
          else { return .viewOnly }

          return .activePair
      }

      // MARK: - Constraint helpers

      /// Returns true if a new column with `renderMode` may be inserted at `index`.
      /// .fileTree: only one allowed, only at the leftmost or rightmost position.
      /// All other render modes: always allowed — duplicates are explicitly permitted.
      public func canInsert(renderMode: PanelID, at index: Int) -> Bool {
          if renderMode == .fileTree {
              let alreadyHasFileTree = columns.contains { $0.renderMode == .fileTree }
              let isEdge = (index == 0 || index == columns.count)
              return !alreadyHasFileTree && isEdge
          }
          return true
      }

      // MARK: - Mutating operations (all called on @MainActor from ContentView)

      /// Add a new column with the given renderMode at destinationIndex.
      /// Callers must validate via canInsert first; this method guards defensively
      /// and no-ops on violation.
      public mutating func addColumn(renderMode: PanelID, documentID: UUID? = nil, at destinationIndex: Int) {
          guard canInsert(renderMode: renderMode, at: destinationIndex) else { return }
          let newCol = PanelColumn(renderMode: renderMode, documentID: documentID)
          let clampedIndex = min(destinationIndex, columns.count)
          columns.insert(newCol, at: clampedIndex)
          normaliseWidths()
      }

      /// Move the column identified by columnID to a new position.
      /// Used when the user drags a column's title bar to a new slot.
      public mutating func moveColumn(id columnID: UUID, to destinationIndex: Int) {
          guard let from = columns.firstIndex(where: { $0.id == columnID }) else { return }
          let renderMode = columns[from].renderMode
          // For fileTree, only allow moving to an edge position.
          if renderMode == .fileTree {
              let isEdge = (destinationIndex == 0 || destinationIndex == columns.count - 1)
              guard isEdge else { return }
          }
          let col = columns.remove(at: from)
          let insertAt = min(destinationIndex, columns.count)
          columns.insert(col, at: insertAt)
          normaliseWidths()
      }

      /// Add documentID as a tab in the column identified by columnID.
      public mutating func addDocument(_ documentID: UUID, toColumnWithID columnID: UUID) {
          guard let i = columns.firstIndex(where: { $0.id == columnID }) else { return }
          guard !columns[i].documentIDs.contains(documentID) else { return }
          columns[i].documentIDs.append(documentID)
      }

      /// Remove documentID from the column identified by columnID.
      /// Prunes the column if it becomes document-less (unless it is a fileTree column).
      public mutating func removeDocument(_ documentID: UUID, fromColumnWithID columnID: UUID) {
          guard let i = columns.firstIndex(where: { $0.id == columnID }) else { return }
          columns[i].documentIDs.removeAll { $0 == documentID }
          if columns[i].activeDocumentIndex >= columns[i].documentIDs.count {
              columns[i].activeDocumentIndex = max(0, columns[i].documentIDs.count - 1)
          }
          removeEmptyColumns()
      }

      /// Remove the column entirely.
      public mutating func removeColumn(id columnID: UUID) {
          columns.removeAll { $0.id == columnID }
          removeEmptyColumns()
      }

      // MARK: - Auto-position helpers

      /// When a text-type file becomes active, move the ACTIVE text editor column
      /// (identified by activeColumnID) to sit immediately beside the File Tree.
      /// File Tree at index 0 → editor moves to index 1.
      /// File Tree at last index → editor moves to index count-2.
      /// No-op if the active column is already adjacent, or if there is no File Tree.
      public mutating func moveActiveEditorAdjacentToFileTree(activeColumnID: UUID) {
          guard let ftIndex = columns.firstIndex(where: { $0.renderMode == .fileTree }),
                let teIndex = columns.firstIndex(where: { $0.id == activeColumnID }),
                columns[teIndex].renderMode == .textEditor else { return }
          let alreadyAdjacent = abs(teIndex - ftIndex) == 1
          if alreadyAdjacent { return }
          let targetIndex = (ftIndex == 0) ? 1 : columns.count - 2
          guard targetIndex >= 0, targetIndex < columns.count, targetIndex != teIndex else { return }
          let col = columns.remove(at: teIndex)
          columns.insert(col, at: min(targetIndex, columns.count))
          normaliseWidths()
      }

      // MARK: - Private helpers

      private mutating func removeEmptyColumns() {
          // Only prune non-fileTree columns that have no documents.
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
  Why: Removing the uniqueness constraint on `renderMode` is the key change that enables four independent text editor columns (or three markdown preview columns, etc.). Columns are identified by their stable `UUID id` — never by render mode. All operations act on column IDs or document IDs. `removeEmptyColumns` only prunes non-fileTree columns that have no documents, preserving the fileTree column even when no workspace is open.

- [ ] **Step 3 — Verify Foundation compiles**
  What: Run `swift build` (or build via Xcode) scoped to `FoundationModule`. Fix any errors before proceeding.
  Why: Nothing else changes until the new model compiles cleanly in isolation.

---

### ⏸ PAUSE 1 — Checkpoint: Foundation new types compile
> Confirm `PanelColumn` and `DynamicPanelLayout` build with zero errors before continuing to Phase 2.

---

## Phase 2 — Update persistence

> Goal: wire the new model into `LayoutState` and `PersistenceService`. The old types are still present; nothing is deleted yet.

- [ ] **Step 4 — Update `LayoutState.swift`**
  What: Replace `panelLayout: PanelLayout` with `dynamicLayout: DynamicPanelLayout`. Replace `visibility: [PanelPosition: Bool]` with nothing — visibility is now implicit (a panel is visible if it appears in `dynamicLayout.columns`). Retain `terminalVisible: Bool`, `recentFiles`, `openDocumentURLs`, `activeDocumentURL` unchanged. Update `CodingKeys`, `init`, and `init(from decoder:)`. Update `LayoutState.default` to use `DynamicPanelLayout.default`. The decode fallback for the new `dynamicLayout` key should be: if the key is absent (old schema) fall back to `.default` — this silently replaces old layouts on first launch with the new schema.
  Why: `LayoutState` is the root Codable type serialised to `layout.json`. It must carry the new layout model and survive a schema mismatch without crashing.

- [ ] **Step 5 — Update `WindowState` references and add `activeColumnID`**
  What:
  - Search for any code that reads `layout.panelLayout` or `layout.visibility` and update it to read `layout.dynamicLayout` instead.
  - Add `var activeColumnID: UUID?` to `WindowState`. This tracks which column currently has keyboard focus. Set it to the `id` of the column whose view calls `onTapGesture` or `onAppear` (any focus event). `ContentView` passes it down to `PanelColumnView` as a binding.
  - Add computed properties:
    ```swift
    var activeColumnRenderMode: PanelID? {
        layout.dynamicLayout.columns.first(where: { $0.id == activeColumnID })?.renderMode
    }
    /// The document ID shown in the active text editor column, or nil if the active
    /// column is not a text editor or has no open document. Used to determine active pairs.
    var activeTextEditorDocumentID: UUID? {
        guard activeColumnRenderMode == .textEditor else { return nil }
        return layout.dynamicLayout.columns.first(where: { $0.id == activeColumnID })?.activeDocumentID
    }
    ```
  - `activeColumnID` is NOT persisted to `layout.json` — it is transient, reset to the first `.textEditor` column (or the first column) on launch.
  Why: `activeColumnID` is the source of truth for which column's border is shown and which column's document the auto-position feature moves. Multiple text editor columns can exist; only the focused one gets the border.

- [ ] **Step 6 — Verify persistence compiles and round-trips**
  What: Build `FoundationModule`. Add a quick manual verification: in the debugger or a unit test, encode `LayoutState.default` to JSON, decode it back, and assert the result equals the original.
  Why: Encoding bugs in `Codable` structs only surface at runtime; catching them here prevents silent data loss.

---

### ⏸ PAUSE 2 — Checkpoint: LayoutState uses new model, builds cleanly
> Confirm `LayoutState.default` references `DynamicPanelLayout`, no references to `panelLayout` or `visibility: [PanelPosition: Bool]` remain, and the module builds with zero errors.

---

## Phase 3 — Rewrite `ContentView`

> Goal: replace the hardcoded three-column `HStack` with a dynamic `ForEach` over `DynamicPanelLayout.columns`. The app should launch and show panels at the end of this phase.

- [ ] **Step 7 — Create `PanelColumnView.swift` in `App-Sputnik/`**
  What: Create a new SwiftUI view `PanelColumnView` that accepts a `Binding<PanelColumn>`, `columnIndex: Int`, `layout: Binding<DynamicPanelLayout>`, `columnRole: DynamicPanelLayout.ColumnRole`, and a `@ViewBuilder` content closure receiving `(renderMode: PanelID, documentID: UUID?, columnRole: DynamicPanelLayout.ColumnRole)`.

  `columnRole` is computed in `ContentView` for each column as `windowState.layout.dynamicLayout.role(of: column.id, activeColumnID: windowState.activeColumnID)` and passed in. The three roles drive behaviour throughout the view:

  | Role | Editing | Help-context | Border |
  |---|---|---|---|
  | `.active` | ✅ full editing | ✅ enabled | ✅ (text editor only) |
  | `.activePair` | ❌ view-only | ✅ enabled (paired preview only) | ❌ |
  | `.viewOnly` | ❌ view-only | ❌ disabled | ❌ |

  The content closure passes `columnRole` through to each panel module so the panel can enforce its own read/write state:
  - `TextEditorPanel` receives `isEditable: Bool = (columnRole == .active)` and sets `NSTextView.isEditable` accordingly. `isSelectable` is always `true` (copy is always allowed).
  - `MarkdownPreviewPanel` and `HTMLPreviewPanel` receive `helpContextEnabled: Bool = (columnRole == .active || columnRole == .activePair)`. When `false`, the right-click "Look Up Help" gesture is suppressed.
  - `PDFViewerPanel` and `FileTreePanel` are unaffected by role (PDF is always view-only; File Tree rename works at the OS level regardless).

  It renders:

  - A **title bar** (28 pt height): on the left, the column's `renderMode.displayBadge` rendered as a small pill (e.g. `MD`, `HTML`, `PDF`). If `renderMode == .pdfViewer` and the active document's `FileType == .image`, show `PNG` instead of `PDF`. If `renderMode == .textEditor`, omit the badge — the border is the indicator. Centre: a drag-handle icon (`line.3.horizontal` SF symbol). Right: a close button (`xmark`, 10 pt). The title bar: (a) has `.onDrag` returning an `NSItemProvider` with `column.id.uuidString` as the payload (column identity, not render mode — critical for multi-column-same-mode scenarios); (b) sets `windowState.activeColumnID = column.id` on tap.

  - A **horizontally scrollable tab bar** (shown only when `column.documentIDs.count > 1`): a `ScrollView(.horizontal, showsIndicators: false)` wrapping an `HStack` of tab buttons, one per `documentID` in `column.documentIDs`. Each button shows the document's filename and the column's `renderMode.displayBadge`. The button for `documentIDs[activeDocumentIndex]` is highlighted (filled capsule, `SputnikColor.accentPrimary` at 15% opacity). Tapping sets `column.activeDocumentIndex` and `windowState.activeColumnID = column.id`. Scrolls naturally when tabs overflow.

  - The **panel content area**: renders the view for `column.renderMode` via the content closure, passing `column.activeDocumentID` so the panel knows which document to display.

  - **Column role border**: apply a border overlay to the entire `VStack`:
    - `columnRole == .active && renderMode == .textEditor && activeDocumentID != nil` → 2 pt `SputnikColor.accentPrimary` solid border (the edit-active signal).
    - `columnRole == .activePair` → 1 pt `SputnikColor.accentPrimary` at 40% opacity dashed border (visually connects the paired preview to the active editor without competing with it).
    - All other cases → no border.
    Both animate with `.easeInOut(duration: 0.15)` so borders fade in/out as focus changes.

  - `.onDrop(of: [UTType.plainText], delegate: ColumnDropDelegate(...))` on the whole column.
  - `.contentShape(Rectangle()).onTapGesture { windowState.activeColumnID = column.id }` to update focus on any click within the column.

  Why: The drag payload is now the column's UUID, not its render mode. This is essential when four columns share the same `renderMode` — dragging by render mode would be ambiguous. The border condition `isActiveColumn && renderMode == .textEditor` means only the focused text editor column is highlighted, regardless of how many text editor columns exist. Preview and PDF columns are identified only by their badge.

- [ ] **Step 8 — Create `ColumnDropDelegate.swift` in `App-Sputnik/`**
  What: Implement `DropDelegate` with:
  - `dropEntered` / `dropExited` — highlight the column drop zone.
  - `validateDrop` — decode the source column UUID from the item provider; look up the column's `renderMode`; return `false` if `renderMode == .fileTree` and the drop target is not the leftmost or rightmost column.
  - `performDrop` — decode source column UUID; call `layout.moveColumn(id: sourceID, to: targetIndex)` to reposition the column. Save the updated layout via `PersistenceService`. (Tab-within-column document reordering is handled separately by the tab bar's own drag within `PanelColumnView`, not by `ColumnDropDelegate`.)
  Why: Drop validation (File Tree constraint) must be in one place, not duplicated across views.

- [ ] **Step 9 — Rewrite `ContentView.body`**
  What: Replace the fixed three-column layout with a dynamic column row and a restructured bottom strip. The new outer structure is:
  ```swift
  VStack(spacing: 0) {
      // Dynamic column row
      HStack(spacing: 1) {
          ForEach(Array(windowState.layout.dynamicLayout.columns.enumerated()), id: \.offset) { index, _ in
              PanelColumnView(
                  column: $windowState.layout.dynamicLayout.columns[index],
                  columnIndex: index,
                  layout: $windowState.layout.dynamicLayout
              ) { panelID in
                  panelContentView(for: panelID)
              }
              if index < windowState.layout.dynamicLayout.columns.count - 1 {
                  ResizeDivider(...)
              }
          }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .overlay { helpPanelOverlay }  // ZStack with opacity, driven by requestedHelpTopic

      Divider()

      // Bottom strip: Terminal (expanding) + optional docked Scratchpad (fixed width)
      HStack(spacing: 0) {
          TerminalView()
              .frame(maxWidth: .infinity)
          if windowState.scratchpadVisible {
              Divider()
              DockedScratchpadPanel(
                  text: $windowState.scratchpadText,
                  width: $windowState.scratchpadDockedWidth   // persisted CGFloat, default 280
              )
          }
      }
      .frame(height: 200)

      Divider()
      StatusBarView()
  }
  ```
  Remove the old `.overlay(alignment: .bottomTrailing) { ScratchpadPanel(...) }` entirely.
  Extract `panelContentView(for panelID: PanelID) -> some View` as a private `@ViewBuilder` helper that switches on `panelID` and returns the correct panel module view. Extract `helpPanelOverlay` as a private `@ViewBuilder` for the existing ZStack-with-opacity help panel routing.
  Why: Docking the Scratchpad into the bottom `HStack` eliminates the floating overlay and gives it a fixed, predictable position next to the Terminal. The ForEach drives the dynamic column count. Both helpers keep `body` readable and keep import-heavy instantiation at the app layer (SR-1).

- [ ] **Step 10 — Create `DockedScratchpadPanel.swift` in `App-Sputnik/`**
  What: Create a simplified replacement for the floating `ScratchpadPanel`. It accepts `text: Binding<String>` and `width: Binding<CGFloat>`. It renders:
  - A title bar: "Scratchpad" label + close button (sets `windowState.scratchpadVisible = false`). No drag-to-reposition handle — the panel is docked and does not move.
  - A left-edge resize handle: a 4 pt `DragGesture` on the leading edge that adjusts `width`, clamped to `200…600` pt.
  - The `ScratchpadTextView` content (reused unchanged from the existing module).
  Add `scratchpadDockedWidth: CGFloat` to `WindowState` (default `280`), persisted via `PersistenceService` in `UserDefaults`. Remove `scratchpadFrame: CGRect` from `WindowState` and `PersistenceService` — it is no longer needed.
  Why: The docked scratchpad is architecturally simpler than the floating version: no absolute positioning, no multi-edge resize, no frame persistence. Reusing `ScratchpadTextView` unchanged avoids touching module 2.4's existing text-view code.

- [ ] **Step 11 — Verify app launches with panels visible**
  What: Run the app. Confirm: default layout (File Tree | Text Editor | Markdown Preview) renders correctly; Terminal fills the bottom strip; Scratchpad appears at the bottom-right when toggled via ⇧⌘K; Scratchpad is not visible on launch (default `scratchpadVisible = false`). No crash on launch.
  Why: Before adding drag interactions, the static rendering and docked Scratchpad must be correct.

---

### ⏸ PAUSE 3 — Checkpoint: app launches with dynamic columns and docked Scratchpad
> Confirm: default layout shows three columns side by side; Terminal fills the bottom strip full-width; Scratchpad appears docked at the bottom-right when toggled (⇧⌘K) and does NOT float on top of panels; `scratchpadFrame` is gone from `WindowState`; no references to `PanelPosition` remain in any file needed for launch.

---

## Phase 4 — Drag-to-move gestures

> Goal: make panels actually moveable. The drop logic is already scaffolded in `ColumnDropDelegate`; this phase wires the drag source and verifies all drop scenarios.

- [ ] **Step 12 — Wire `.onDrag` to panel title bars**
  What: In `PanelColumnView`, attach `.onDrag { NSItemProvider(object: column.activePanel.rawValue as NSString) }` to the title bar `HStack`. Set the drag preview to a rounded rectangle labelled with the panel name (`DragPreview` SwiftUI modifier or `onDrag(_, preview:)`).
  Why: The drag payload is just a `String` (the `PanelID.rawValue`) — simple and Sendable. The column drop delegate decodes it back to a `PanelID`.

- [ ] **Step 13 — Add between-column drop zones**
  What: Insert a thin (8 pt wide) invisible `DropZoneView` between each pair of adjacent `PanelColumnView` items in the `ForEach`. `DropZoneView` highlights on hover and calls `layout.moveToNewColumn(panel, at: insertionIndex)` on drop. This is how a panel gets its own new column rather than becoming a tab.
  Why: Without explicit between-column drop zones, every drop lands on an existing column and becomes a tab. The two drop targets (between-columns = new column, on-column = tab) give the user full control.

- [ ] **Step 14 — Enforce File Tree constraint**
  What: In both `ColumnDropDelegate.validateDrop` and `DropZoneView`, check: if the dragged panel is `.fileTree`, reject the drop unless the insertion index is 0 or `columns.count` (i.e. leftmost or rightmost position). Show a red highlight instead of the normal blue one when rejection applies. Also enforce the constraint in `DynamicPanelLayout.moveToNewColumn` as a defensive guard: if `canPlace(.fileTree, at:)` returns false, the mutation is a no-op and logs a warning via `ErrorReporting`.
  Why: The File Tree edge constraint must be enforced at two levels — UI (immediate visual feedback) and model (prevents impossible states from persisting to disk).

- [ ] **Step 15 — Wire text-editor auto-position on document activation**
  What: In `ContentView`, extend the existing `.onChange(of: appState.activeDocumentID)` handler. After the document is resolved, check whether the newly active document is a text-type file (`.text`, `.markdown`, `.html`, `.ascii`). If it is, and `windowState.activeColumnID` points to a `.textEditor` column, call `windowState.layout.dynamicLayout.moveActiveEditorAdjacentToFileTree(activeColumnID: windowState.activeColumnID!)` and persist. Do not call this for `.pdf`, `.binary`, or `.unknown`.
  Why: Now that multiple text editor columns can exist, the auto-position targets the specific focused editor column (identified by `activeColumnID`), not just "the text editor column". The logic in `DynamicPanelLayout` already handles this via `activeColumnID`.

- [ ] **Step 16 — Test all scenarios manually**
  What: Verify each of the following works correctly:
  - [ ] Drag Editor to the right of Markdown Preview → new column appears on the right.
  - [ ] Drag Markdown Preview onto Editor column → Markdown Preview becomes a tab inside the Editor column; scrollable tab bar appears.
  - [ ] Drag a third panel onto that same column → three tabs in the tab bar; scroll the tab bar to confirm all three are reachable.
  - [ ] Click each tab in a multi-tab column → active panel switches correctly each time.
  - [ ] Drag File Tree from left edge to between Editor and Markdown → drop is rejected with red highlight; File Tree stays put.
  - [ ] Drag File Tree to the right of all columns → File Tree moves to the rightmost position correctly.
  - [ ] Start with only PDF Viewer absent from the layout → confirm other panels expand to fill the space; no empty placeholder column appears.
  - [ ] Close a column with the ✕ button on its title bar → column disappears; remaining columns expand; layout saves.
  - [ ] Open app after saving layout → all columns, tab assignments, and active tabs restore correctly.
  - [ ] Toggle Scratchpad (⇧⌘K) → docked Scratchpad panel appears and disappears at the bottom right; Terminal strip width adjusts.
  - [ ] With File Tree at far left and Editor three columns away from it: open a text file → Editor column jumps to column 1 (immediately right of File Tree).
  - [ ] With File Tree at far right and Editor three columns away from it: open a text file → Editor column jumps to the column immediately left of File Tree.
  - [ ] Open a PDF file → Editor does NOT jump; PDF Viewer activates in its own column; layout unchanged.
  - [ ] Editor already adjacent to File Tree: open a text file → no column movement occurs.
  - [ ] **Four text editor columns — only one active**: open four files, one in each of four `.textEditor` columns. Click the leftmost → border appears on it; attempt to type in it → text is entered. Click a different column → border moves; the first column becomes view-only (typing does nothing; selecting and copying works).
  - [ ] **Non-active text editor is view-only**: in a non-active text editor column, attempt to type → no text is entered. Attempt to select and copy → succeeds. Attempt to right-click Look Up Help → no help panel opens.
  - [ ] **Active text editor + three Markdown preview columns**: one `.textEditor` column (solid border), three `.markdownPreview` columns each showing a different `.md` file with `MD` badge. The Markdown preview column showing the SAME document as the active editor gets a dashed border (active pair). The other two get no border. Right-click in the active-pair MD preview → help context opens. Right-click in a non-paired MD preview → no help context.
  - [ ] **Active text editor + three HTML preview columns**: same active-pair rule with `.htmlPreview` / `HTML` badge — only the column showing the same document as the active editor gets the dashed border and help-context.
  - [ ] **Active text editor + three PDF viewer columns**: `.pdfViewer` columns are never active pair (PDFs cannot be the paired preview of a text editor) — all three get no border and no help-context regardless of document match.
  - [ ] Active text editor column with an open document → thin coloured border visible; all other columns (regardless of render mode) have no border.
  - [ ] Close all documents in the active text editor column → border disappears even though the column still exists.
  - [ ] Markdown Preview column title bar shows `MD` badge; HTML Preview shows `HTML`; PDF Viewer shows `PDF`; Text Editor shows no badge (border is the indicator).
  - [ ] Open an image file in PDF Viewer → badge reads `PNG` not `PDF`.
  - [ ] Column with two document tabs: scrollable tab bar shows both with badges; clicking each tab switches the displayed document.
  Why: These are the canonical scenarios from the feature spec; all must pass before cleanup.

---

### ⏸ PAUSE 4 — Checkpoint: all scenarios pass
> All twenty-one test scenarios above pass. File Tree constraint is enforced at both UI and model levels. Scrollable tab bar shows and scrolls correctly. PDF-absent layout allocates no empty column. Scratchpad docks/undocks correctly. Text editor auto-positions next to File Tree on text file open, but does not move for PDFs or when already adjacent. Column type badges are visible in title bars and tab buttons. Text Editor border appears only when a document is open.

---

## Phase 5 — Remove legacy code and update guides

> Goal: delete `PanelPosition`, `PanelLayout`, and every reference to them. Update all affected Module Guides.

- [ ] **Step 17 — Delete `PanelPosition.swift`**
  What: Delete `2 Foundation/2.4 UI and UX/PanelPosition.swift`. Search the entire codebase for any remaining references to `PanelPosition` and remove or replace them.
  Why: The type is fully replaced by the column-index-based model. Keeping it would leave dead code that could confuse future contributors.

- [ ] **Step 18 — Delete `PanelLayout.swift`**
  What: Delete `2 Foundation/2.4 UI and UX/PanelLayout.swift`. Search for any remaining references to `PanelLayout` and replace with `DynamicPanelLayout`.
  Why: Fully replaced by `DynamicPanelLayout`. No migration path needed — the user confirmed the legacy structure is being replaced, not kept.

- [ ] **Step 19 — Remove floating Scratchpad remnants**
  What: Delete or gut `ScratchpadPanel.swift` (the floating version). Remove `scratchpadFrame: CGRect` from `WindowState` and from `PersistenceService`'s `UserDefaults` key list. Remove the `.overlay(alignment: .bottomTrailing)` call in `ContentView`. Confirm `ScratchpadTextView.swift` is untouched — it is reused by `DockedScratchpadPanel`.
  Why: The floating scratchpad code is now dead. Leaving it in place would create two competing Scratchpad implementations.

- [ ] **Step 20 — Final compile and warning check**
  What: Build the full project (`swift build` or Xcode). Confirm zero errors and zero warnings. Pay specific attention to: unused `import` statements in files that used to reference `PanelPosition`; any `<!-- assumed -->` comments in guide files that reference the deleted types; any remaining references to `scratchpadFrame`.
  Why: The plan's success condition requires a clean build. Warnings are treated as issues here because they often indicate dangling references to deleted types.

- [ ] **Step 21 — Update Module Guide: 2.4 UI and UX**
  What: Update `1 Setup/Module Guides/2 Foundation/2.4 UI and UX/guide.md`:
  - Replace the fixed-slot diagram with a dynamic-column diagram showing the default layout and the File Tree edge constraint.
  - Replace Scratchpad floating-overlay description with the docked-panel description.
  - Update Key Types: remove `PanelPosition`, update `PanelLayout` → `DynamicPanelLayout`, add `PanelColumn`, add `PanelColumnView`, add `ColumnDropDelegate`, add `DockedScratchpadPanel`.
  - Update Data Flow section to describe drag-to-move, scrollable tabs, and File Tree constraint.
  - Add Invariants section: (1) File Tree always at index 0 or last; (2) Terminal always full-width bottom; (3) Scratchpad always docked bottom-right.
  - Set `status: active` and `last_updated: 2026-06-12`.
  Why: The guide is the source of truth for the module's design intent; it must match the code.

- [ ] **Step 22 — Update Module Guide: 2.5 Persistence**
  What: Update `1 Setup/Module Guides/2 Foundation/2.5 Persistence/guide.md`:
  - Update `LayoutState` description to reflect `dynamicLayout: DynamicPanelLayout` replacing the old fields.
  - Update `UserDefaults` key list: remove `scratchpadFrame`, add `scratchpadDockedWidth`.
  - Note the old-schema fallback behaviour.
  - Set `status: active` and `last_updated: 2026-06-12`.
  Why: Guide must reflect the new `layout.json` schema and updated UserDefaults keys.

- [ ] **Step 23 — Update Module Guide: 2.0 App Overview**
  What: Update the layout diagram in `1 Setup/Module Guides/2 Foundation/2.0 App overview/guide.md` to show the new dynamic column arrangement with the docked Scratchpad at the bottom right. Update the Technical Summary: `PanelLayout` → `DynamicPanelLayout`; `ScratchpadPanel` floating → `DockedScratchpadPanel` docked. Set `last_updated: 2026-06-12`.
  Why: The App Overview diagram is the first thing a new contributor reads; it must reflect the real layout model.

---

### ⏸ PAUSE 5 — Final checkpoint before closeout
> Confirm: zero build errors/warnings. All three guides updated. `PanelPosition.swift`, `PanelLayout.swift`, and floating `ScratchpadPanel` code deleted. `scratchpadFrame` removed from `WindowState` and `UserDefaults`. All fourteen scenarios still pass after cleanup.

---

## Risks and Constraints

- **`PanelPosition` is referenced in `LayoutState.visibility`** — the field is being removed entirely; visibility is now implicit (a panel is visible if it appears in `dynamicLayout.columns`). Any code that reads `layout.visibility[.left]` must be updated to check `dynamicLayout.columns.contains(where: { $0.panels.contains(.fileTree) })` or equivalent.
- **File Tree invariant — enforced at two levels**: (1) `ColumnDropDelegate.validateDrop` and `DropZoneView` reject illegal drops in the UI; (2) `DynamicPanelLayout.canPlace(_:at:)` + a guard in `moveToNewColumn` reject them at the model level. Both must be consistent. The invariant: `fileTree` is only valid at `index == 0` or `index == columns.count - 1`.
- **Dynamic occupancy — no reserved slots**: Columns only exist when panels are placed in them. If PDF Viewer has never been added to the layout, there is no PDF Viewer column and no empty placeholder. `DynamicPanelLayout.default` does not include PDF Viewer or HTML Preview; they only appear when the user drags them in. `removeEmptyColumns()` must always run after any panel is removed.
- **Scratchpad docking — state simplification**: `scratchpadFrame: CGRect` is removed from `WindowState` and `PersistenceService`. Only `scratchpadVisible: Bool` and `scratchpadDockedWidth: CGFloat` remain. Any code that reads `scratchpadFrame` will fail to compile — use this as a checklist signal that all floating-scratchpad code has been found and removed.
- **Column role is computed, never stored**: `DynamicPanelLayout.role(of:activeColumnID:)` is a pure function called fresh on every render. Do not cache it or store it on `PanelColumn` — it would go stale the moment `activeColumnID` changes.
- **Active pair is strictly document-scoped**: a `.markdownPreview` or `.htmlPreview` column is only `.activePair` if its `activeDocumentID` exactly matches the active text editor column's `activeDocumentID`. Two columns showing the same filename in different directories are NOT the same document — UUID match only.
- **PDF columns are never active pair**: even if a PDF viewer shows the same URL as the active editor, it is not an active pair (PDFs are not editable sources). The `role(of:)` method already enforces this via the `renderMode == .markdownPreview || .htmlPreview` guard.
- **`NSTextView.isEditable` must be set before the view appears**: if set after, the text view may briefly accept input. Set it synchronously in `makeNSView` based on the `isEditable` flag passed from `PanelColumnView`.
- **Multiple columns, same render mode**: the drag payload is now the column's `UUID`, not its `PanelID`. If it were `PanelID`, dragging one of four `.textEditor` columns would be ambiguous. `ColumnDropDelegate` and `DropZoneView` must decode UUID, not `PanelID`.
- **`activeColumnID` is transient**: it lives on `WindowState` and is NOT in `layout.json`. On launch, set it to `dynamicLayout.columns.first(where: { $0.renderMode == .textEditor })?.id ?? dynamicLayout.columns.first?.id`. Never persist it.
- **`panelContentView(for:)` now receives a `documentID`**: the helper signature becomes `panelContentView(renderMode: PanelID, documentID: UUID?) -> some View`. Each panel module must accept an optional document ID to know which document to display. Verify each panel module's init accepts this before Phase 3.
- **`ContentView` imports all panel modules** — this is intentional and correct; Foundation never imports panel modules. The `panelContentView(for:)` helper must stay in `App-Sputnik/` only.
- **SwiftUI `ForEach` with stable ID** — use `ForEach(columns, id: \.id)` since `PanelColumn` now conforms to `Identifiable`. This is safe across reorders because the UUID is stable.
- **Resize dividers** — proportional `width` values must renormalise to sum to 1.0 after any mutation. `DynamicPanelLayout.normaliseWidths()` handles this; ensure it is called after every column insertion or removal.
- **Help panels** — `.asciiArtHelp`, `.markdownHelp`, `.htmlHelp`, `.grammarHelp` in `PanelID` are NOT part of the column system. They remain overlay views driven by `windowState.requestedHelpTopic`. Do not add them to any `DynamicPanelLayout`.

## Files Affected

- `2 Foundation/2.4 UI and UX/PanelID.swift` — updated: `displayBadge: String?` computed property added
- `2 Foundation/2.4 UI and UX/PanelColumn.swift` — NEW: the atomic column type (panels list + activeIndex + width)
- `2 Foundation/2.4 UI and UX/DynamicPanelLayout.swift` — NEW: replaces `PanelLayout` + `PanelPosition`; owns File Tree constraint logic
- `2 Foundation/2.4 UI and UX/PanelLayout.swift` — DELETED
- `2 Foundation/2.4 UI and UX/PanelPosition.swift` — DELETED
- `2 Foundation/2.4 UI and UX/ScratchpadPanel.swift` — DELETED (floating version replaced by docked version)
- `2 Foundation/2.4 UI and UX/ScratchpadTextView.swift` — unchanged; reused by `DockedScratchpadPanel`
- `2 Foundation/2.5 Persistence/LayoutState.swift` — updated: `dynamicLayout` replaces `panelLayout`+`visibility`; old-schema fallback
- `2 Foundation/2.2 Global State Management/WindowState.swift` — `scratchpadFrame` removed; `scratchpadDockedWidth: CGFloat` added; `activeColumnID: UUID?` added (transient, not persisted); `layout.panelLayout` → `layout.dynamicLayout`
- `App-Sputnik/ContentView.swift` — rewritten body: ForEach columns + docked bottom strip; `panelContentView(for:)` + `helpPanelOverlay` helpers
- `App-Sputnik/PanelColumnView.swift` — NEW: column wrapper with title bar (badge + drag handle) + scrollable tab bar (badges) + Text Editor border + drag source + drop target
- `App-Sputnik/ColumnDropDelegate.swift` — NEW: drop validation + File Tree constraint enforcement
- `App-Sputnik/DropZoneView.swift` — NEW: thin between-column drop target for new-column insertion
- `App-Sputnik/DockedScratchpadPanel.swift` — NEW: simplified docked scratchpad (no floating, no frame persistence)
- `1 Setup/Module Guides/2 Foundation/2.4 UI and UX/guide.md` — updated diagram, key types, invariants, docked Scratchpad
- `1 Setup/Module Guides/2 Foundation/2.5 Persistence/guide.md` — updated LayoutState + UserDefaults keys
- `1 Setup/Module Guides/2 Foundation/2.0 App overview/guide.md` — updated layout diagram + technical summary

## Closeout

- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (all twenty-five scenarios pass; four same-mode columns work with one active border; File Tree always at edge; scrollable tabs + badges work; Text Editor border appears only on the focused editor column with an open document; PNG badge overrides PDF for images; Scratchpad docked; PDF-absent layout allocates no empty column; Editor auto-positions on text file open; old types deleted; guides updated)
- [ ] Module Guides updated: 2.0, 2.4, 2.5 (`status` + `last_updated`)
- [ ] Changes committed: `[2 Foundation] Dynamic Panel Layout`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
