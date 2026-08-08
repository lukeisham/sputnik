---
plan: Dynamic Panels — Part 2 of 3: UI Shell
module: App-Sputnik (ContentView + new views) + 2 Foundation (WindowState)
created: 2026-06-12
status: pending
depends_on: "Part 1 — Data Model and Persistence (complete)"
unlocks: "Part 3 — Drag Interactions and Cleanup"
related_issues: none
---

## Purpose
Replace the hardcoded three-column `HStack` in `ContentView` with a dynamic `ForEach` over `DynamicPanelLayout.columns`. Wire the column role system (active border, active-pair dashed border, render-mode toggle pills), dock the Scratchpad, and verify the app launches with the correct visual structure. Drag interactions are NOT implemented in this plan — that is Part 3.

## Success Condition
- App launches showing the default layout (File Tree | Text Editor | Markdown Preview) rendered via the new `ForEach`.
- Clicking a column focuses it (solid border on active Text Editor column).
- Clicking a non-active column that is text-sourced shows render-mode toggle pills where the file extension supports it.
- Toggling a view-only column switches its display; clicking it to focus auto-reverts to text.
- Dashed border appears on a preview column when its document matches the active editor's document.
- Terminal fills the bottom strip full-width. Scratchpad appears docked beside Terminal on ⇧⌘K.
- Zero errors, zero warnings.

---

## Step 1 — Create `PanelColumnView.swift`

New file: `App-Sputnik/PanelColumnView.swift`

Accepts:
- `column: Binding<PanelColumn>`
- `columnIndex: Int`
- `layout: Binding<DynamicPanelLayout>`
- `columnRole: DynamicPanelLayout.ColumnRole`
- `@ViewBuilder content: (PanelID, UUID?, DynamicPanelLayout.ColumnRole) -> some View`

`columnRole` is computed in `ContentView` for each column as:
```swift
windowState.layout.dynamicLayout.role(of: column.id, activeColumnID: windowState.activeColumnID)
```

### Title bar (28 pt height)

Left side:
- **Badge pill**: `column.renderMode.displayBadge` as a small rounded pill (omit if `renderMode == .textEditor` — the border is its indicator). If `renderMode == .pdfViewer` and the active document's `FileType == .image`, show `"PNG"` instead.
- **Render-mode toggle pills** (view-only text-sourced columns only):
  - Condition: `columnRole == .viewOnly && (column.renderMode == .textEditor || column.originalRenderMode == .textEditor)`
  - Determine `availableModes: [PanelID]` from the active document's file extension via `appState.document(for: column.activeDocumentID)?.url.pathExtension`:
    - `.md` / `.markdown` → `[.textEditor, .markdownPreview]`
    - `.html` / `.htm` → `[.textEditor, .htmlPreview]`
    - anything else → hide pills (don't show toggle)
  - Render as compact pill buttons (`TXT`, `MD`, `HTML`). Current `renderMode` pill is filled (solid capsule, `SputnikColor.accentPrimary` at 20% opacity). Others are outlined.
  - Tapping calls `layout.toggleRenderMode(ofColumnID: column.id, to: selectedMode)`.

Centre: drag-handle icon (`line.3.horizontal` SF symbol). This is the visual affordance for Part 3 drag — the `.onDrag` modifier is added in Part 3.

Right: close button (`xmark`, 10 pt) — calls `layout.removeColumn(id: column.id)`, then sets `windowState.activeColumnID` to the first remaining column if the closed column was active.

The title bar as a whole: `.onTapGesture` calls `layout.revertToggleIfNeeded(forColumnID: column.id)` FIRST, then sets `windowState.activeColumnID = column.id`.

### Scrollable tab bar

Shown only when `column.documentIDs.count > 1`. A `ScrollView(.horizontal, showsIndicators: false)` wrapping an `HStack` of tab buttons, one per document ID. Each button shows the document filename + `renderMode.displayBadge`. The active tab (matching `activeDocumentIndex`) is highlighted (filled capsule, `SputnikColor.accentPrimary` at 15% opacity). Tapping sets `column.activeDocumentIndex` and `windowState.activeColumnID = column.id`.

### Panel content area

Calls the `content` closure with `(column.renderMode, column.activeDocumentID, columnRole)`.

The caller (`ContentView`) passes these through to each panel module:
- `TextEditorPanel` receives `isEditable: Bool = (columnRole == .active)`. Set `NSTextView.isEditable` synchronously in `makeNSView` — do not set it after the view appears. `isSelectable` is always `true`.
- `MarkdownPreviewPanel` and `HTMLPreviewPanel` receive `helpContextEnabled: Bool = (columnRole == .active || columnRole == .activePair)`. When `false`, suppress right-click "Look Up Help".
- `PDFViewerPanel` and `FileTreePanel` are unaffected by role.

### Column role border

Applied as an overlay on the entire `VStack`:
- `columnRole == .active && renderMode == .textEditor && activeDocumentID != nil` → 2 pt solid `SputnikColor.accentPrimary`
- `columnRole == .activePair` → 1 pt dashed `SputnikColor.accentPrimary` at 40% opacity
- all other cases → no border

Animate with `.easeInOut(duration: 0.15)`.

### Drop target (scaffold)

Add `.onDrop(of: [UTType.plainText], delegate: ColumnDropDelegate(...))` — `ColumnDropDelegate` is a stub at this stage (Part 3 fills it in). This ensures the file compiles without needing Part 3 to be complete first.

### Focus

`.contentShape(Rectangle()).onTapGesture { layout.revertToggleIfNeeded(forColumnID: column.id); windowState.activeColumnID = column.id }` on the whole column so any click within it registers focus.

---

## Step 2 — Create `ColumnDropDelegate.swift` (stub)

New file: `App-Sputnik/ColumnDropDelegate.swift`

Stub implementation that compiles but does nothing yet. Full logic (UUID decode, File Tree constraint, `moveColumn` call) is added in Part 3.

```swift
struct ColumnDropDelegate: DropDelegate {
    func performDrop(info: DropInfo) -> Bool { false }
}
```

---

## Step 3 — Rewrite `ContentView.body`

File: `App-Sputnik/ContentView.swift`

Replace the fixed HStack + right column with:

```swift
VStack(spacing: 0) {
    HStack(spacing: 1) {
        ForEach(Array(windowState.layout.dynamicLayout.columns.enumerated()), id: \.offset) { index, _ in
            let col = windowState.layout.dynamicLayout.columns[index]
            let role = windowState.layout.dynamicLayout.role(of: col.id,
                                                              activeColumnID: windowState.activeColumnID)
            PanelColumnView(
                column: $windowState.layout.dynamicLayout.columns[index],
                columnIndex: index,
                layout: $windowState.layout.dynamicLayout,
                columnRole: role
            ) { panelID, documentID, columnRole in
                panelContentView(renderMode: panelID, documentID: documentID, columnRole: columnRole)
            }
            if index < windowState.layout.dynamicLayout.columns.count - 1 {
                ResizeDivider(/* wire to column widths */)
            }
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay { helpPanelOverlay }

    Divider()

    HStack(spacing: 0) {
        TerminalView()
            .frame(maxWidth: .infinity)
        if windowState.scratchpadVisible {
            Divider()
            DockedScratchpadPanel(
                text: $windowState.scratchpadText,
                width: $windowState.scratchpadDockedWidth
            )
        }
    }
    .frame(height: 200)

    Divider()
    StatusBarView()
}
```

Remove the old `.overlay(alignment: .bottomTrailing) { ScratchpadPanel(...) }` entirely.

Extract two private helpers:
- `panelContentView(renderMode: PanelID, documentID: UUID?, columnRole: DynamicPanelLayout.ColumnRole) -> some View` — `@ViewBuilder` switch over `renderMode` returning the correct panel module.
- `helpPanelOverlay` — existing ZStack-with-opacity help panel routing, unchanged logic, moved to a `@ViewBuilder` var.

---

## Step 4 — Create `DockedScratchpadPanel.swift`

New file: `App-Sputnik/DockedScratchpadPanel.swift`

Accepts `text: Binding<String>` and `width: Binding<CGFloat>`.

Renders:
- Title bar: "Scratchpad" label + close button (`windowState.scratchpadVisible = false`). No drag handle — docked, does not move.
- Left-edge resize handle: 4 pt `DragGesture` adjusting `width`, clamped to `200…600` pt.
- `ScratchpadTextView` content (reuse unchanged).

In `WindowState`:
- Add `scratchpadDockedWidth: CGFloat` (default `280`), persisted via `UserDefaults`.
- Remove `scratchpadFrame: CGRect` from `WindowState` and `PersistenceService`. Any file that reads `scratchpadFrame` will now fail to compile — use this as a search signal that all floating-scratchpad code is found.

---

## Step 5 — Verify: app launches

Run the app. Confirm:
- [ ] Default layout (File Tree | Text Editor | Markdown Preview) renders as three columns side by side.
- [ ] Terminal fills the bottom strip full-width.
- [ ] ⇧⌘K toggles the docked Scratchpad beside Terminal; it does NOT float on top of panels.
- [ ] Clicking any column focuses it; the active text editor column shows the coloured border when a document is open.
- [ ] Clicking a view-only text column showing a `.md` file shows `TXT | MD` pills; tapping `MD` switches it to Markdown preview; tapping the column to focus it reverts to text.
- [ ] Dashed border appears on a preview column whose document matches the active editor's document.
- [ ] No crash. No layout regressions.

---

### ⏸ PAUSE — Checkpoint

> Confirm before handing off to Part 3:
> - App launches. Default layout renders correctly.
> - Terminal full-width at bottom; Scratchpad docks correctly.
> - Active column border, active-pair dashed border, and view-only state all work.
> - Render-mode toggle pills appear for `.md` and `.html` files; auto-revert on focus works.
> - `scratchpadFrame` removed; `DockedScratchpadPanel` replaces the floating overlay.
> - Zero errors, zero warnings.
> - **Drag interactions not yet wired** — columns are not yet draggable (Part 3).

---

## Risks and Notes

- `NSTextView.isEditable` must be set in `makeNSView`, not after the view appears — do not set it in `updateNSView` on first render.
- The `ForEach` uses `\.offset` not `\.element.id` because `Binding` subscript requires index-based access. If SwiftUI reorder animations are needed later, revisit — for now index-based is correct.
- `ColumnDropDelegate` is a stub in this plan. The `.onDrop` modifier must still compile — verify.
- `helpPanelOverlay` logic is unchanged from the current `rightColumn` — only moves from a `@ViewBuilder var` returned from the old right-column helper into an overlay on the full column row. The ZStack-with-opacity approach is preserved.
- `panelContentView(renderMode:documentID:columnRole:)` must stay in `App-Sputnik/` — `ContentView` imports all panel modules; `Foundation` must never import them (SR-1).

---

## Step 6 — Update tests and guides

### Tests

Update `App-Sputnik/Tests/` (or the relevant test target) to cover the new surface:

- **`PanelColumnViewTests`** — verify column role border logic (active solid, activePair dashed, other none); verify render-mode pill visibility conditions (`.md` / `.html` extensions show pills, others hide); verify close button removes the column and reassigns `activeColumnID`.
- **`DockedScratchpadPanelTests`** — verify width clamping (`200…600` pt); verify close sets `scratchpadVisible = false`.
- **`WindowStateTests`** — verify `scratchpadDockedWidth` persists via `UserDefaults`; verify `scratchpadFrame` no longer exists (compilation check is sufficient).
- **`ContentViewTests`** — verify `panelContentView` returns the correct panel type for each `PanelID`; verify `helpPanelOverlay` builds without crashing when help is toggled.

Run the full test suite; confirm zero failures before proceeding.

### Update guides

Invoke `!UpdateGuides` for each module touched by this plan:

- `!UpdateGuides: 2 Foundation` — reflect `scratchpadDockedWidth` added, `scratchpadFrame` removed from `WindowState`.
- `!UpdateGuides: App-Sputnik` — reflect `PanelColumnView`, `ColumnDropDelegate` (stub), `DockedScratchpadPanel` added; `ContentView` body rewritten with `ForEach` + `panelContentView` + `helpPanelOverlay`.

---

## Files Changed

- `App-Sputnik/PanelColumnView.swift` — NEW
- `App-Sputnik/ColumnDropDelegate.swift` — NEW (stub)
- `App-Sputnik/DockedScratchpadPanel.swift` — NEW
- `App-Sputnik/ContentView.swift` — body rewritten; `helpPanelOverlay` + `panelContentView` extracted
- `2 Foundation/2.2 Global State Management/WindowState.swift` — `scratchpadDockedWidth` added; `scratchpadFrame` removed
