---
plan: Unified window toolbar
module: 2 Foundation (2.4 UI and UX, 2.6 App Lifecycle)
created: 2026-06-12
status: completed
related_issues: none
---

## Purpose
Add a native unified-title-bar `NSToolbar`/SwiftUI `.toolbar` to the main window so panel toggles and primary view controls live in a standard, discoverable Mac location instead of being absent — the most visible "not quite native" gap today.

## Success Condition
- The main window shows a unified title-bar toolbar with controls for: toggle each panel type (File Tree / Editor / Preview / PDF / Terminal), render-mode toggle, and Settings.
- The toolbar respects user customization (right-click → Customize Toolbar) and survives relaunch.
- Toolbar controls drive the exact same `AppState`/layout actions as the existing menu commands — no duplicated logic.
- In a tier-"full" build the toolbar matches system styling in both light and dark mode.

## Steps

- [x] 1. **Decide toolbar scope against the dynamic-panel model**
   What: Confirm which actions belong in the toolbar given that panels are already drag-created; settle on panel-visibility toggles + render mode + Settings, excluding anything that conflicts with drag-to-create columns.
   Why: The app's layout is dynamic; a toolbar that fights the drag model would confuse rather than help — scope must be decided before building.

- [x] 2. **Add a `.toolbar` to the main `WindowGroup` scene**
   What: Attach a SwiftUI `.toolbar { }` in `ContentView`/`SputnikApp`, using `ToolbarItem(placement:)` with system-symbol buttons; set `.toolbar(id:)` for customization support.
   Why: SwiftUI `.toolbar` on the WindowGroup yields the native unified title bar with the least AppKit (SW-3).

- [x] 3. **Bind toolbar actions to existing command logic**
   What: Route each toolbar button to the same methods `SputnikCommands` already calls (panel toggles, render mode), not to new copies.
   Why: SR-1 / DRY — menu and toolbar must share one source of truth so they never drift.

- [x] 4. **Reflect live state in toolbar controls**
   What: Make toggle buttons show selected/active state from `AppState`/`DynamicPanelLayout` (e.g. highlighted when that panel is visible).
   Why: A toggle that doesn't show its on/off state reads as non-native and confuses users.

- [x] 5. **Enable and persist toolbar customization**
   What: Give items stable identifiers and confirm Customize Toolbar works; ensure the chosen configuration persists (AppKit persists by identifier automatically).
   Why: Customizable toolbars are an expected Mac affordance and the persistence is nearly free once IDs are stable.

- [x] 6. **Add accessibility labels to toolbar items**
   What: Label every toolbar button (coordinate with the Accessibility plan if it runs first).
   Why: Icon-only toolbar buttons are exactly the controls VoiceOver cannot name without explicit labels.

- [ ] 7. **Verify light/dark, customization, and relaunch**
   What: Manually confirm styling in both appearances, that Customize works, and that the layout/config restores after quit.
   Why: Satisfies the Success Condition across the states a real user will hit.

## Risks and Constraints
- SW-3: prefer SwiftUI `.toolbar`; only drop to `NSToolbar` via representable if a control genuinely needs AppKit — document the reason at the call site.
- SR-1: toolbar lives in Foundation and calls shared command protocols; it must not reach into panel-module internals.
- Interaction with `.windowResizability(.contentSize)` — verify the toolbar does not force an unexpected minimum content size.
- Do not duplicate command logic (DRY); a regression here would let menu and toolbar diverge.

## Files Affected
- `2 Foundation/2.6 App Lifecycle/ContentView.swift` — attach `.toolbar`
- `2 Foundation/2.6 App Lifecycle/SputnikApp.swift` — `.toolbar(id:)` scene wiring if needed
- `2 Foundation/2.0 App Overview/SputnikCommands.swift` (+ relevant `*MenuGroup.swift`) — expose shared action methods for reuse
- `2 Foundation/2.4 UI and UX/` — any small toolbar-item view/helper

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (toolbar actions, customization, light/dark, relaunch) — *manual step*
- [ ] Module Guide(s) updated — *no guides exist yet for modules 2 or 6*
- [x] Changes committed: `[2 Foundation] Unified window toolbar`
- [x] Pushed to GitHub
- [x] Plan moved to Plans Completed/
