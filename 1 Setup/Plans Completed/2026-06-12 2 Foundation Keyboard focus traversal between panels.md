---
plan: Keyboard focus traversal between panels
module: 2 Foundation (2.4 UI and UX, 2.1 Inter-panel communication)
created: 2026-06-12
status: pending
related_issues: none
---

## Purpose
Let power users move keyboard focus between panels (and to the active document within a column) without the mouse, with a clear visible focus indicator — replacing today's near-absent focus handling (2 `@FocusState` uses).

## Success Condition
- A documented shortcut (e.g. ⌃⇥ / ⌃⌥→ ) cycles focus across visible panels in a predictable order; the focused panel shows a clear focus ring/indicator.
- Each window has a sensible default first responder on open (the active editor).
- Tabbing never traps focus or sends it to an off-screen/hidden panel.
- Focus order is stable and matches visual left-to-right, top-to-bottom layout.

## Steps

- [ ] 1. **Define a panel-focus model in Foundation**
   What: Add a `FocusablePanel` identifier set and a `@FocusState`-backed focus coordinator (e.g. `PanelFocusCoordinator`) in 2.4, keyed by the same `PanelID`/column identity the layout already uses.
   Why: SR-1 — focus traversal spans panels owned by different modules, so the coordinator belongs in Foundation, consumed by each panel.

- [ ] 2. **Compute traversal order from the live layout**
   What: Derive the focus ring order from `DynamicPanelLayout`'s ordered columns (skipping hidden panels), so order follows the visible arrangement including the Terminal.
   Why: A hard-coded order would break the moment a user re-arranges or hides a column; it must be derived, not fixed.

- [ ] 3. **Attach focus bindings to each panel root**
   What: Bind each panel's root view `.focused($focus, equals: <panelID>)` and the active editor as the default; have panel modules consume the Foundation coordinator.
   Why: Connects the shared model to module-owned views without modules importing each other (SR-1).

- [ ] 4. **Add the cycle-focus commands**
   What: In `SputnikCommands`, add "Focus Next/Previous Panel" commands with shortcuts that advance the coordinator's selection; also add a direct "Focus Editor/Terminal" pair.
   Why: Keyboard users expect explicit, discoverable commands (and menu entries) for focus movement.

- [ ] 5. **Render a visible focus indicator**
   What: Show a focus ring / accent outline on the focused panel, distinct from the existing active-column border, and ensure it works with Differentiate Without Color.
   Why: Focus that can't be seen is unusable; it must be distinguishable from the active-document border which is a different concept.

- [ ] 6. **Set the default first responder per window**
   What: On window open/restore, route initial focus to the active editor (or File Tree if no document is open).
   Why: A window that opens with nothing focused forces an immediate mouse click, defeating keyboard flow.

- [ ] 7. **Verify no focus traps and correct skip behaviour**
   What: Manually cycle in single- and multi-column layouts, with panels hidden/shown and the Terminal toggled; confirm hidden panels are skipped and focus never sticks.
   Why: Satisfies the Success Condition and catches the classic focus-trap regressions.

## Risks and Constraints
- SR-1: the coordinator is the only cross-panel focus authority; panels do not move focus into each other directly.
- SwiftUI `@FocusState` does not cross some `NSViewRepresentable` boundaries cleanly — the editor/terminal (AppKit-backed) may need a small first-responder bridge; document it at the call site (SW-3).
- Shortcut choices must not collide with existing menu shortcuts (36 already defined) or with Terminal key handling — audit before assigning.
- Keep focus computation a cheap main-actor operation (SR-4).

## Files Affected
- `2 Foundation/2.4 UI and UX/PanelFocusCoordinator.swift` — new shared focus model
- `2 Foundation/2.1 Inter-panel communication/` — focus-routing protocol if needed
- `2 Foundation/2.0 App Overview/ViewMenuGroup.swift` / `SputnikCommands.swift` — focus commands + shortcuts
- `2 Foundation/2.4 UI and UX/PanelColumnView.swift` — focus binding + indicator
- Panel-module roots (editor, terminal, file tree, previews, PDF) — `.focused` bindings / first-responder bridge

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (cycle order, indicator, default responder, no traps)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[2 Foundation] Keyboard focus traversal between panels`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
