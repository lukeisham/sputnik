---
plan: Implement range selection for editing tools
module: 10 ASCII Studio
created: 2026-07-02
status: pending
related_issues: ISS-195
---

## Purpose
Wire up the drag-to-select gesture in the editable canvas so the already-built "Select"/"Replace" toolbar and `ASCIIImageEditor.replaceSelection(with:)` become reachable, instead of being permanently dead UI.

## Success Condition
- Clicking and dragging across multiple cells in the editable canvas highlights the dragged range.
- With a range selected, typing a character into the "Char" field and clicking "Replace" replaces every cell in the selection, registers one undoable action, and updates `hasManualEdits`.
- Clicking a single cell without dragging still behaves as today (tap-to-edit via `selectedCell`) — this plan adds range selection alongside, it does not replace single-cell tap-to-edit.
- ⌘Z after a range replace undoes the entire batch in one step (matching the existing `replaceSelection` undo registration).
- Selection visually clears on a new conversion/load (consistent with existing `hasManualEdits`/discard-warning behavior) and on Escape or clicking elsewhere.

## Steps

- [ ] 1. **Decide the selection model: rectangular vs. linear range**
   What: `ASCIIImageEditor.Selection` is currently a flat `startIndex...endIndex` range over the row-major grid array — which means a "selection" spanning multiple rows currently covers whole intervening rows, not a clean rectangle (compare `TerminalTextView.selectedCells`, which explicitly handles first/last-row column clamping for exactly this reason). Decide whether Studio selections should be a true rectangle (row/col bounds, matching user expectation for a character-grid canvas) or keep the simpler flat-range model and document the limitation. Recommend rectangular, given the canvas is visually a grid.
   Why: This decision shapes every subsequent step — get it right before writing gesture code, rather than discovering the mismatch after `GridNSView` drag handling is built against the wrong model.

- [ ] 2. **Add rectangular selection state (if step 1 chooses rectangular)**
   What: If moving to a rectangle, either extend `ASCIIImageEditor.Selection` with `startRow`/`startCol`/`endRow`/`endCol` (deriving the flat `range` as a computed helper used only for the actual mutation), or introduce a new `RectSelection` type alongside the existing flat one and have `replaceSelection` iterate the rectangle's cells directly instead of the flat range.
   Why: Supports intuitive multi-row drag selection matching what a character-grid canvas user expects (a rectangle of cells, not "everything between these two flat indices including full intervening rows").

- [ ] 3. **Implement drag gesture in `GridNSView`**
   What: Add `mouseDown`/`mouseDragged`/`mouseUp` (or reuse `mouseDown` for the anchor and add `mouseDragged`) to `GridNSView`, converting each event's location to a (row, col) cell position (reusing/adapting the existing `mouseDown` hit-testing math), and call a new `onSelectionDrag: ((CellRange) -> Void)?` closure that `MonoGridView` wires to `editor.updateSelection(from:to:)` (new method) rather than the existing single-cell `onCellTap`.
   Why: ISS-195 — this is the actual missing piece; `GridNSView` currently only supports a single `mouseDown` tap, never a drag.

- [ ] 4. **Distinguish tap vs. drag**
   What: In `GridNSView`, track the mouse-down cell; if `mouseUp` fires with the same cell as `mouseDown` (no drag occurred), call the existing `onCellTap` path (single-cell tap-to-edit); if the cell changed during `mouseDragged`, treat it as a range selection instead.
   Why: Preserves the existing, working tap-to-edit UX exactly as-is while adding range selection as a distinct interaction, per the Success Condition.

- [ ] 5. **Render the selection highlight in `draw(_:)`**
   What: In `GridNSView.draw(_:)`, in addition to the existing `selectedCell` single-cell highlight, iterate the active range selection's cells and apply the same (or a visually distinct) highlight fill.
   Why: Without visual feedback, drag-selection is unusable — the user needs to see what's selected before clicking Replace.

- [ ] 6. **Wire the "Select" button and clear-selection affordance**
   What: Decide what the currently-empty "Select" button should do now that drag-selection exists — likely options: remove the button entirely (drag *is* select, no explicit mode needed), or repurpose it as "Select All" / "Clear Selection." Implement whichever fits; if removed, delete the dead button and its `Divider()`.
   Why: ISS-195 flagged this button as dead code; once drag-selection is real, the button either needs a real purpose or should go.

- [ ] 7. **Add unit tests**
   What: In `Tests/ASCIIStudioModuleTests.swift`, test the new selection-update logic (rectangle bounds computation, or flat-range computation if step 1 kept the simpler model) as pure functions independent of `NSView`; test that `replaceSelection` correctly covers a multi-row rectangular range and registers one undo action.
   Why: The selection geometry math is the part most likely to have off-by-one errors (compare the Terminal's own selection-geometry bug, ISS-186, found in this same review pass) — pure-function extraction makes it testable without `NSView`/`AppKit`.

- [ ] 8. **Manual verification pass**
   What: Run the app; drag-select a multi-row range in the canvas, replace it, undo it; confirm single-cell tap-to-edit still works unaffected; confirm selection clears appropriately on re-conversion.
   Why: Drag gesture feel and visual correctness are best confirmed hands-on.

## Risks and Constraints
- SR-6: keep the new drag-selection logic in `MonoGridView.swift` (where the existing tap-to-edit logic lives) rather than spreading it across files, unless it grows large enough to warrant its own file (a `CellRange` type might reasonably live in its own small file, matching the module's existing pattern of `ASCIIArt.swift`/`RampSwatchView.swift` as focused single-purpose files).
- Do not regress single-cell tap-to-edit — it's a working, tested feature; range selection is additive.
- If step 1 concludes a full rectangular model is too large a change for this plan's scope, a smaller acceptable fallback is: keep the flat-range model, but visually and behaviorally document that selection spans "logical" grid positions rather than a clean on-screen rectangle for multi-row drags — note this explicitly in the guide rather than silently shipping a surprising interaction.

## Files Affected
- `10 ASCII Studio/Sources/ASCIIImageEditor.swift` — `Selection` type (possibly extended/replaced), new `updateSelection`/range-replace logic
- `10 ASCII Studio/Sources/MonoGridView.swift` — drag gesture handling, selection-range rendering
- `10 ASCII Studio/Sources/ASCIIStudioImageView.swift` — "Select" button behavior change/removal
- `10 ASCII Studio/Tests/ASCIIStudioModuleTests.swift` — new test cases

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[10 ASCII Studio] Implement range selection for editing tools`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
