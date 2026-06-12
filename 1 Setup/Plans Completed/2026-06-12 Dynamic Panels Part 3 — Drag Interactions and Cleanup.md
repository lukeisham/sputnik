---
plan: Dynamic Panels — Part 3 of 3: Drag Interactions and Cleanup
module: App-Sputnik + 2 Foundation (all modules)
created: 2026-06-12
status: pending
depends_on: "Part 2 — UI Shell (complete)"
unlocks: nothing (final part)
related_issues: none
---

## Purpose
Wire all drag-to-move interactions, enforce the File Tree edge constraint at both UI and model levels, add between-column drop zones, wire the text editor auto-position feature, and run all test scenarios. Then remove all legacy layout types and update the three affected Module Guides.

## Success Condition
- Panels are draggable by their title bar and can be dropped to reorder columns or become tabs.
- File Tree cannot be dropped anywhere except the leftmost or rightmost column; rejected drops show a red highlight.
- Between-column drop zones create new columns on drop.
- Opening a text file moves the active editor column adjacent to the File Tree (if not already).
- All 33 test scenarios in Step 5 pass.
- `PanelPosition.swift`, `PanelLayout.swift`, and the floating `ScratchpadPanel` are deleted.
- Zero errors, zero warnings. All three Module Guides updated.

---

## Step 1 — Wire `.onDrag` to column title bars

File: `App-Sputnik/PanelColumnView.swift`

In the title bar, attach:
```swift
.onDrag {
    NSItemProvider(object: column.id.uuidString as NSString)
}
```
The payload is the column's `UUID` string — NOT `PanelID.rawValue`. This is critical: four `.textEditor` columns share the same `PanelID`; only their UUIDs are distinct.

Set the drag preview to a rounded rectangle labelled with `renderMode.displayBadge ?? "panel"`.

---

## Step 2 — Create between-column drop zones

File: `App-Sputnik/DropZoneView.swift` (new)

An 8 pt wide invisible view inserted between each pair of adjacent `PanelColumnView` items in `ContentView`'s `ForEach`. On hover it highlights (blue tint). On drop it calls `layout.addColumn(renderMode: sourceRenderMode, at: insertionIndex)` — creating a new column rather than adding a tab.

In `ContentView`, replace the `ResizeDivider` between columns with a `ZStack` of `ResizeDivider` and `DropZoneView(insertionIndex: index + 1, layout: $windowState.layout.dynamicLayout)`.

---

## Step 3 — Fill in `ColumnDropDelegate`

File: `App-Sputnik/ColumnDropDelegate.swift`

Replace the stub with the full implementation:

- `dropEntered` / `dropExited`: highlight the column drop zone (blue tint for valid, red for rejected).
- `validateDrop`: decode the source column UUID from the item provider; look up `renderMode` in `layout.columns`; return `false` if `renderMode == .fileTree` and the target column is not the leftmost or rightmost.
- `performDrop`: decode source UUID; call `layout.moveColumn(id: sourceUUID, to: targetIndex)` to reposition the dragged column so it becomes a tab in the target column. Persist the updated layout via `PersistenceService`.

The File Tree edge constraint must also be guarded in `DynamicPanelLayout.moveColumn` (already implemented in Part 1) — this is the defensive second layer.

---

## Step 4 — Wire text editor auto-position on file open

File: `App-Sputnik/ContentView.swift`

Extend the existing `.onChange(of: appState.activeDocumentID)` handler:

```swift
.onChange(of: appState.activeDocumentID) { _, _ in
    Task {
        try? await editorViewModel.openDocument(appState.activeDocument?.url)
        // Auto-position: move active text editor column adjacent to File Tree
        // when the newly opened document is a text-type file.
        if let fileType = appState.activeDocument?.fileType,
           fileType == .text || fileType == .markdown || fileType == .html || fileType == .ascii,
           let activeColID = windowState.activeColumnID {
            windowState.layout.dynamicLayout.moveActiveEditorAdjacentToFileTree(activeColumnID: activeColID)
            // persist
        }
    }
}
```

Do NOT call this for `.pdf`, `.binary`, or `.unknown` file types.

---

## Step 5 — Test all scenarios

Run the app and verify each scenario:

### Drag and drop
- [ ] Drag Editor title bar to the right of Markdown Preview → new column appears on the right.
- [ ] Drag Markdown Preview onto Editor column → Markdown Preview becomes a tab inside the Editor column; scrollable tab bar appears.
- [ ] Drag a third panel onto that same column → three tabs in the tab bar; scroll the tab bar to confirm all three are reachable.
- [ ] Click each tab in a multi-tab column → active panel switches correctly.
- [ ] Drag File Tree from left edge to between Editor and Markdown → drop is rejected; red highlight shown; File Tree stays put.
- [ ] Drag File Tree to the right of all columns → File Tree moves to the rightmost position correctly.

### Layout and visibility
- [ ] Start with PDF Viewer absent from the layout → other panels expand; no empty placeholder column.
- [ ] Close a column with the ✕ button → column disappears; remaining columns expand; layout saves.
- [ ] Open app after saving layout → all columns, tab assignments, and active tabs restore correctly.

### Scratchpad
- [ ] Toggle Scratchpad (⇧⌘K) → docked Scratchpad appears/disappears at the bottom right; Terminal width adjusts.

### Auto-position
- [ ] File Tree at far left; Editor three columns away: open a text file → Editor jumps to column 1 (immediately right of File Tree).
- [ ] File Tree at far right; Editor three columns away: open a text file → Editor jumps to column immediately left of File Tree.
- [ ] Open a PDF file → Editor does NOT jump; PDF Viewer activates; layout unchanged.
- [ ] Editor already adjacent to File Tree: open a text file → no column movement.

### Column roles and borders
- [ ] **Four text editor columns — only one active**: open four files, one per column. Click the leftmost → border appears; type → text is entered. Click another column → border moves; previous column becomes view-only (typing does nothing; copy works).
- [ ] **Non-active text editor is view-only**: type in a non-active text editor → nothing entered. Select + copy → succeeds. Right-click Look Up Help → no help panel opens.
- [ ] **Active text editor + three Markdown preview columns**: active editor shows `readme.md`; the MD preview column showing `readme.md` gets dashed border + help-context; the other two MD previews (different files) get no border and no help-context.
- [ ] **Active text editor + three HTML preview columns**: same active-pair rule with `.htmlPreview`.
- [ ] **Active text editor + three PDF viewer columns**: no PDF column ever gets a dashed border or help-context, regardless of document match.
- [ ] Active text editor column with an open document → coloured border visible. All other columns have no border.
- [ ] Close all documents in the active text editor column → border disappears; column still exists.

### Badges
- [ ] Markdown Preview title bar shows `MD` badge; HTML Preview shows `HTML`; PDF Viewer shows `PDF`; Text Editor shows no badge.
- [ ] Open an image file in PDF Viewer → badge reads `PNG` not `PDF`.
- [ ] Column with two document tabs: scrollable tab bar shows both with badges; clicking each tab switches the displayed document.

### Render-mode toggle
- [ ] View-only column showing a `.md` file: title bar shows `TXT | MD` pills; `TXT` pill is filled. Tap `MD` → column switches to Markdown preview (`MD` badge; rendered output shown).
- [ ] View-only column showing an `.html` file: title bar shows `TXT | HTML`. Tap `HTML` → column switches to HTML preview.
- [ ] View-only column showing a plain `.txt` file: NO toggle pills shown.
- [ ] Toggle a column to `.markdownPreview`, quit the app, relaunch → column is still in `.markdownPreview` mode (`originalRenderMode` restored from `layout.json`).
- [ ] Active text editor shows `readme.md`; a view-only column is also showing `readme.md` and has been toggled to `.markdownPreview` → dashed active-pair border appears on that column. Toggle it back to `TXT` → dashed border disappears.
- [ ] Tap anywhere inside a toggled (`.markdownPreview`) column → it auto-reverts to `.textEditor` and becomes active (solid border).
- [ ] **Four-column scenario**: active `.textEditor` (left, solid border) + one native `.markdownPreview` (same doc, dashed) + two toggled `.markdownPreview` columns (different docs, no border) → only the matching-doc column has the dashed border.

---

### ⏸ PAUSE — Checkpoint: all scenarios pass

> All 33 scenarios above pass. Do not proceed to cleanup until every item is checked.

---

## Step 6 — Delete `PanelPosition.swift`

Delete `2 Foundation/2.4 UI and UX/PanelPosition.swift`. Grep the entire project for `PanelPosition` — remove or replace every remaining reference.

---

## Step 7 — Delete `PanelLayout.swift`

Delete `2 Foundation/2.4 UI and UX/PanelLayout.swift`. Grep for `PanelLayout` — replace every remaining reference with `DynamicPanelLayout`.

---

## Step 8 — Remove floating Scratchpad remnants

- Delete or gut the floating `ScratchpadPanel.swift` (the overlay version).
- Confirm `scratchpadFrame` does not appear anywhere in `WindowState`, `PersistenceService`, or `UserDefaults` key lists.
- Confirm `ScratchpadTextView.swift` is untouched — it is reused by `DockedScratchpadPanel`.

---

## Step 9 — Final compile and warning check

Build the full project. Zero errors, zero warnings. Specifically check:
- No unused `import` statements left in files that referenced `PanelPosition`.
- No remaining references to `scratchpadFrame`.
- No `<!-- assumed -->` comments in guide files that reference deleted types.

---

## Step 10 — Update Module Guide: 2.4 UI and UX

File: `1 Setup/Module Guides/2 Foundation/2.4 UI and UX/guide.md`

- Replace the fixed-slot diagram with a dynamic-column diagram showing the default layout and the File Tree edge constraint.
- Replace Scratchpad floating-overlay description with the docked-panel description.
- Update Key Types: remove `PanelPosition`; `PanelLayout` → `DynamicPanelLayout`; add `PanelColumn`, `PanelColumnView`, `ColumnDropDelegate`, `DropZoneView`, `DockedScratchpadPanel`.
- Update Data Flow: describe drag-to-move, scrollable tabs, File Tree constraint, render-mode toggle.
- Add / update Invariants: (1) File Tree always at index 0 or last; (2) Terminal always full-width bottom; (3) Scratchpad always docked bottom-right; (4) column role computed fresh each render, never cached.
- Set `status: active`, `last_updated: 2026-06-12`.

---

## Step 11 — Update Module Guide: 2.5 Persistence

File: `1 Setup/Module Guides/2 Foundation/2.5 Persistence/guide.md`

- Update `LayoutState` description: `dynamicLayout: DynamicPanelLayout` replaces old fields.
- Update `UserDefaults` key list: remove `scratchpadFrame`; add `scratchpadDockedWidth`.
- Note old-schema fallback behaviour.
- Set `status: active`, `last_updated: 2026-06-12`.

---

## Step 12 — Update Module Guide: 2.0 App Overview

File: `1 Setup/Module Guides/2 Foundation/2.0 App overview/guide.md`

- Update layout diagram to show dynamic columns and docked Scratchpad.
- Update Technical Summary: `PanelLayout` → `DynamicPanelLayout`; floating `ScratchpadPanel` → `DockedScratchpadPanel` docked.
- Set `last_updated: 2026-06-12`.

---

### ⏸ PAUSE — Final checkpoint

> - Zero build errors/warnings.
> - All 33 scenarios still pass after cleanup.
> - `PanelPosition.swift`, `PanelLayout.swift`, floating `ScratchpadPanel` deleted.
> - `scratchpadFrame` gone from `WindowState` and `UserDefaults`.
> - All three Module Guides updated.

---

## Closeout

- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] All 33 scenarios pass.
- [ ] Module Guides 2.0, 2.4, 2.5 updated (`status` + `last_updated`).
- [ ] Changes committed: `[2 Foundation] Dynamic Panel Layout`
- [ ] Pushed to GitHub.
- [ ] This plan and Parts 1 and 2 moved to `Plans Completed/`.

---

## Risks and Notes

- Drag payload is the column UUID string — NOT `PanelID.rawValue`. `ColumnDropDelegate` decodes a `UUID`, not a `PanelID`. Four `.textEditor` columns are indistinguishable by render mode; only their UUIDs are distinct.
- File Tree constraint enforced at two levels: `ColumnDropDelegate.validateDrop` (UI rejection) and `DynamicPanelLayout.moveColumn` guard (model rejection). Both must be consistent.
- Auto-position targets the focused editor column (`activeColumnID`), not just any text editor column. Multiple text editors can be open; only the active one moves.
- `revertToggleIfNeeded` must be called BEFORE setting `activeColumnID` in the focus tap gesture. Order matters.
- After all legacy deletions, run a full grep for `PanelPosition`, `PanelLayout`, and `scratchpadFrame` to confirm zero hits before signing off.

## Files Changed

- `App-Sputnik/PanelColumnView.swift` — `.onDrag` added
- `App-Sputnik/ColumnDropDelegate.swift` — stub replaced with full implementation
- `App-Sputnik/DropZoneView.swift` — NEW
- `App-Sputnik/ContentView.swift` — between-column drop zones; auto-position `onChange` extended
- `2 Foundation/2.4 UI and UX/PanelPosition.swift` — DELETED
- `2 Foundation/2.4 UI and UX/PanelLayout.swift` — DELETED
- `2 Foundation/2.4 UI and UX/ScratchpadPanel.swift` — DELETED (floating version)
- `1 Setup/Module Guides/2 Foundation/2.4 UI and UX/guide.md` — updated
- `1 Setup/Module Guides/2 Foundation/2.5 Persistence/guide.md` — updated
- `1 Setup/Module Guides/2 Foundation/2.0 App overview/guide.md` — updated
