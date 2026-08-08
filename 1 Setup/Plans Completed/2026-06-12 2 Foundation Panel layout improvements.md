---
plan: Panel layout improvements — resize, per-window persistence, panel distinctions
module: 2 Foundation (2.4 UI and UX / 2.5 Persistence / 2.2 Global State) + App-Sputnik shell
created: 2026-06-12
status: draft
related_issues: (log via !TrackIssues before implementation — see Risks)
---

## Purpose
Make the dynamic panel layout feel intentional: real drag-to-resize and reorder with clear visual feedback, column widths that actually persist per window, and an unambiguous visual identity for every panel type (Editor, Preview, View, Terminal, File Tree, Scratchpad).

## Background (verified against source)
Three gaps drive this plan:

1. **`ResizeDivider` is a stub.** `App-Sputnik/ResizeDivider.swift` is a 1 pt static rectangle whose own doc comment reads *"Drag-resize interaction is added in Part 3. For now this is a static separator."* There is no `DragGesture`.
2. **`PanelColumn.width` is dead state.** `DynamicPanelLayout` stores a per-column `width` and `normaliseWidths()` spreads it evenly, but `App-Sputnik/ContentView.swift` (the column `HStack`, lines ~50–96) never reads `col.width` — every column gets `maxWidth: .infinity`, so they always split evenly. `normaliseWidths()` is then called on every `addColumn` / `moveColumn` / `removeDocument`, resetting any width to even. Widths are serialized into `layout.json` and `WindowDescriptor`, but the value is meaningless because nothing applies it.
3. **Panel identity is inconsistent.** Columns show a badge pill from `PanelID.displayBadge` (`PanelColumnView.badgePill`), but `.textEditor` deliberately omits its badge, and the Terminal (a pinned strip, not a column) and the Scratchpad (a docked panel, not a column) have no badge mechanism at all. "View" panels are view-only columns distinguished only by border style. There is no single place that names all six panel kinds consistently.

## Success Condition
- **Resize:** Dragging the divider between two columns smoothly reallocates width between exactly those two neighbours, with a sensible minimum width (no column collapses to zero), a resize cursor on hover, and a haptic detent at the even-split point. The new widths visibly persist for the rest of the session.
- **Reorder:** Dragging a column shows clear feedback — the drag source dims, and the valid drop target/insertion point highlights — and the File Tree edge constraint still holds (it can only land at index 0 or last). A subtle haptic confirms the snap (already present).
- **Persistence:** Closing and reopening a window restores that window's exact column widths, order, and render modes — not an even split. Per-window layouts do not bleed into each other.
- **Distinctions:** Every panel kind (Editor, Markdown Preview, HTML Preview, PDF/Image View, Terminal, File Tree, Scratchpad) has a consistent, legible identity (badge/title) derived from one source of truth, distinguishable without relying on colour alone (per the existing Differentiate-Without-Color note in `PanelColumnView`).
- No force-unwraps; no regression to the focus ring, role border, tab bar, or column add/remove behaviour.

## Steps

### Workstream A — Drag, resize & snap polish (2.4 / shell)

- [ ] 1. **Make `col.width` authoritative in `ContentView`'s column `HStack`.**
   What: Replace the even `maxWidth: .infinity` columns with a `GeometryReader`-driven layout that sizes each `PanelColumnView` to `col.width * availableWidth` (reserving the fixed 8 pt divider gaps). Keep a floor (e.g. `minColumnWidth`) so a column never renders below a usable size.
   Why: Width is already modelled and persisted but never honoured; until the frame respects `col.width`, resize and persistence are both invisible. This is the keystone step — everything else in A and B depends on it.

- [ ] 2. **Implement real drag-resize in `ResizeDivider`.**
   What: Add a horizontal `DragGesture` that converts the drag translation into a width delta and shifts it between the two adjacent columns (index `i` and `i+1`) via a new `DynamicPanelLayout` mutation, e.g. `resize(columnAt:by:availableWidth:minWidth:)`, that clamps both neighbours to `minWidth` and conserves their summed width. Add `.onHover` → `NSCursor.resizeLeftRight` and an `NSHapticFeedbackManager` `.alignment` detent when the split crosses 50/50. Update the file's doc comment (it still says resize is "added in Part 3").
   Why: This is the missing interaction. Confining the delta to the two neighbours (rather than re-normalising all columns) keeps resize predictable and local, matching how users expect a splitter to behave.

- [ ] 3. **Stop `normaliseWidths()` from clobbering user-set widths.**
   What: Change `DynamicPanelLayout` so add/move/remove rescale widths *proportionally* to still sum to 1.0 (give a newly inserted column a default share and shrink the others pro-rata; on removal redistribute the freed share pro-rata) instead of resetting everything to `1/n`. Keep an explicit "reset to even" affordance for the user, but never trigger it implicitly. Audit every current `normaliseWidths()` caller (`addColumn`, `moveColumn`, `removeEmptyColumns`).
   Why: Today any resize is wiped the next time a column is added, moved, or a tab closes. Proportional rescaling preserves the user's intent through structural changes.

- [ ] 4. **Add reorder drag feedback.**
   What: In `PanelColumnView`, dim the drag-source column (≈0.4 opacity) while it is being dragged — mirroring the pattern already used for tab reordering (ISS-019). In `DropZoneView` / `ColumnDropDelegate`, highlight the active insertion gap on `dropEntered` / `dropExited` and clear it on drop. Keep the existing snap haptic.
   Why: The reorder mechanism works (`onDrag` UUID payload → `ColumnDropDelegate.moveColumn`) but is invisible mid-drag; users get no signal of where the column will land or that a drag is even in progress.

### Workstream B — Per-window layout persistence (2.5 / 2.2 / 2.6)

- [ ] 5. **Confirm and fix the per-window width round-trip.**
   What: Trace the restore path (`AppDelegate` → `persistence.restoreWindows()` → `WindowDescriptor.layout` → each window's `WindowState.layout.dynamicLayout`) and the save path (`saveWindows(descriptors)`). Verify that after Step 1–3, the live `col.width` values are the ones serialized and that restore re-applies them to that specific window — not the global `layout.json` default. Add/adjust a Codable default so older files without meaningful widths fall back gracefully (the decoder already tolerates a missing `dynamicLayout`).
   Why: The plumbing exists but has only ever carried even widths; once widths are real, this is where "remember panel layouts per window" is actually delivered, and where a per-window vs global mix-up would surface.

- [ ] 6. **Decide and document the global-vs-per-window precedence.**
   What: `flushLayout(layoutState)` writes a single global `layout.json` while `saveWindows` writes per-window descriptors. Pin down which wins on launch for a restored window vs a brand-new window, and make new windows inherit a sensible default (global last-used) while restored windows use their own descriptor. Record the rule in the 2.5 guide.
   Why: Two persistence channels touch the same `DynamicPanelLayout`; without an explicit precedence rule (the spirit of ISS-001), restored windows could be silently overwritten by the global blob.

### Workstream C — Panel distinctions (2.4 / shell / 2.0)

- [ ] 7. **Single source of truth for panel identity.**
   What: Extend the `PanelID` identity surface (or add a small companion) so every panel kind exposes a consistent display name *and* badge: Editor, MD, HTML, PDF/PNG (the existing image override), View, File Tree — and give the Terminal strip and Scratchpad panel equivalent identity descriptors even though they are not columns. Route `PanelColumnView.resolvedBadge`, the tab bar badge, and any menu labels through this one source.
   Why: Identity is currently scattered (`displayBadge` with a `.textEditor` omission, an ad-hoc `"PNG"` override, no descriptor for Terminal/Scratchpad). One source removes the drift and makes "clarify distinctions" enforceable.

- [ ] 8. **Give the Editor and the Terminal/Scratchpad a visible, distinct identity.**
   What: Reconsider the `.textEditor` "no badge" rule so the Editor is positively identified rather than identified by absence; add a lightweight title/badge to the Terminal strip and the docked Scratchpad consistent with the column badges. Ensure all distinctions read without colour alone (shape/text), consistent with the `roleBorder` / `focusIndicator` Differentiate-Without-Color notes already in `PanelColumnView`.
   Why: The Editor, Terminal, and Scratchpad are the three panels a user works in most and the three with the weakest current labelling; "View" vs "Editor" vs "Preview" must be obvious at a glance.

- [ ] 9. **Verify menu / accessibility naming matches the new identities.**
   What: Reconcile panel names used in `ViewMenuGroup` / `SputnikCommands` and the VoiceOver labels in `PanelColumnView` (`columnAccessibilityName`, close-button hint) with the Step 7 source of truth so menus, badges, and screen-reader output all say the same thing.
   Why: Distinctions that exist only visually still confuse keyboard and VoiceOver users; the existing accessibility pass (commit b9b61de) should not regress.

### Workstream D — Guides & issues

- [ ] 10. **Log the discovered defects as issues, then update guides.**
   What: Via `!TrackIssues`, log (a) `ResizeDivider` never implemented its drag interaction, and (b) `PanelColumn.width` is persisted but never applied / reset by `normaliseWidths`. Then update the **2.4 UI and UX** guide (resize behaviour, panel-identity source, `ResizeDivider`/`DropZoneView` roles) and the **2.5 Persistence** guide (per-window width round-trip + precedence rule from Step 6); bump `last_updated` / `last_verified`.
   Why: Per CLAUDE.md working conventions — issue first, fix second; guides are the source of truth and must not lag this change.

## Risks and Constraints
- **Touches Foundation (module 2) — flagged per the `!GenerateAPlan` rule.** `DynamicPanelLayout` (2.4) is consumed by `ContentView`, `PanelColumnView`, `ColumnDropDelegate`, `DropZoneView`, `WindowState`, and the persistence layer; the `normaliseWidths` change (Step 3) and the new `resize` mutation alter behaviour every consumer relies on. Re-verify add / move / remove / file-tree-edge paths after each change.
- **One module at a time / cross-module change → plan first (this doc).** Do Workstream A before B (persistence is meaningless until widths are honoured), and A before C only where C touches the same `PanelColumnView` body.
- **Invariants to preserve:** `DynamicPanelLayout.columns` is never empty; at most one `.fileTree`, only at index 0 or last; widths must always sum to ~1.0 after any mutation (new invariant introduced by Steps 2–3 — assert it).
- **No force-unwraps** in the resize math or width application (guard against zero/negative available width from `GeometryReader` during layout passes).
- **Low-RAM / UI-thread rules (SR-3/SW-4):** resize updates fire continuously during a drag — mutate `dynamicLayout` directly (cheap value-type copy) without triggering persistence on every frame; persist on drag-end / the existing flush cycle, not per delta.
- **Differentiate Without Color:** any new identity or feedback cue (Steps 4, 7, 8) must encode meaning in shape/text/position, not colour alone, matching the existing notes in `PanelColumnView`.

## Files Affected
- `App-Sputnik/ResizeDivider.swift` — implement drag-resize, hover cursor, detent haptic; fix stale doc comment (Steps 2).
- `App-Sputnik/ContentView.swift` — apply `col.width` to column frames via `GeometryReader`; min-width floor (Step 1).
- `2 Foundation/2.4 UI and UX/DynamicPanelLayout.swift` — new `resize(...)` mutation; proportional rescale replacing implicit `normaliseWidths()` reset; width-sum invariant (Steps 2–3).
- `App-Sputnik/PanelColumnView.swift` — drag-source dim; panel-identity wiring; Editor/accessibility labels (Steps 4, 7, 8, 9).
- `App-Sputnik/ColumnDropDelegate.swift`, `App-Sputnik/DropZoneView.swift` — insertion-gap highlight on enter/exit (Step 4).
- `2 Foundation/2.5 Persistence/LayoutState.swift`, `WindowDescriptor.swift`, `PersistenceService`/`FilePersistenceService.swift` — verify per-window width round-trip; global-vs-per-window precedence (Steps 5–6).
- `2 Foundation/2.6 App Lifecycle/AppDelegate.swift` — restore/save precedence wiring if Step 6 requires it.
- `App-Sputnik/DockedScratchpadPanel.swift`, `7 Terminal/TerminalView.swift` — Terminal/Scratchpad identity badges (Steps 7–8).
- `2 Foundation/2.0 App Overview/ViewMenuGroup.swift`, `SputnikCommands.swift` — menu naming reconciliation (Step 9).
- Guides: `1 Setup/Module Guides/2 Foundation/2.4 UI and UX/guide.md`, `…/2.5 Persistence/guide.md`; `1 Setup/References/Issues.md` (Step 10).
