---
plan: Window & tab management fixes
module: 2 Foundation (2.0 App Overview, 2.1 Inter-Panel, 2.4 UI/UX, 2.6 App Lifecycle)
created: 2026-06-10
status: complete
related_issues: ISS-017, ISS-018, ISS-019, ISS-020
---

## Purpose
Fix four window/tab defects in Foundation so multi-window/multi-tab management is correct and free of stale duplicate code: remove the dead duplicate app entry point (ISS-017), make "Merge All Windows" actually close the emptied native windows (ISS-018), add drag-to-reorder tabs that persist (ISS-019), and route "Move Tab to New Window" through the unsaved-changes guard (ISS-020).

## Success Condition
- `swift build` succeeds; `2 Foundation/Package.swift` no longer needs the `SputnikApp.swift` exclude and the stale duplicate file is gone (ISS-017).
- Invoking **Window ▸ Merge All Windows** with 2+ windows open leaves exactly one window on screen containing all unique tabs; no empty windows linger (ISS-018).
- A tab can be dragged left/right within `DocumentTabBar` to a new position; the new order survives quit-and-relaunch (ISS-019).
- **Window ▸ Move Tab to New Window** on a dirty tab shows the same unsaved-changes prompt as closing it, and cancelling leaves the tab in place (ISS-020).
- No new force-unwraps; all four affected modules still build independently (SR-1, SR-2).

## Steps

- [x] 1. **Re-read source-of-truth before touching code**
   What: Re-read `App-Sputnik/SputnikApp.swift`, `SputnikCommands.swift` (Window menu), `DocumentTabBar.swift`, `AppInterPanelRouter.swift`, `WindowState.swift`/`AppState.swift`, and `WindowDescriptor.swift`.
   Why: These are the exact files the four fixes touch; confirm no behaviour has shifted since the issues were logged so the plan stays accurate.

- [x] 2. **ISS-017 — delete the stale duplicate entry point**
   What: Delete `2 Foundation/2.6 App Lifecycle/SputnikApp.swift` (the 505-line `@main` duplicate) and remove the now-orphaned `exclude: ["2.6 App Lifecycle/SputnikApp.swift"]` entry from `2 Foundation/Package.swift`.
   Why: The file is dead code excluded from the build by one fragile hardcoded path; its header comment is also false. Removing both the file and the exclude eliminates the double-`@main` hazard at its root rather than papering over it.

- [x] 3. **ISS-017 — confirm FoundationModule still builds @main-free**
   What: Run `swift build` from the repo root and from `2 Foundation/`; verify no "main attribute can only apply to one type" or missing-exclude errors.
   Why: Proves the duplicate was genuinely unused and the package manifests are consistent after removal (SR-1).

- [x] 4. **ISS-020 — add a dirty-aware "move tab" path in the router**
   What: In `AppInterPanelRouter` (2.1), add `func moveActiveTabToNewWindow() async` that runs the same `isDirty` confirmation used by `close(_:)`, and only on confirmation performs the remove-from-source / create-window / insert-into-target sequence (delegating the actual `AppState`/`WindowState` mutations, not doing file IO).
   Why: SR-1 requires cross-window orchestration to go through the Foundation router, and SR-2 forbids the silent data-loss path the current direct mutation in `SputnikCommands` creates.

- [x] 5. **ISS-020 — repoint the menu command at the router**
   What: Replace the inline body of "Move Tab to New Window" in `SputnikCommands.windowMenu` with a call to the new router method (via the same wiring `close` uses); keep `openWindow(id:"main", value:)` for surfacing the new scene.
   Why: The command must reuse the guarded path so dirty tabs prompt before moving, matching the tab-bar close button's behaviour.

- [x] 6. **ISS-018 — give the router/AppState a way to close a window's NSWindow**
   What: Add a helper that, given a `WindowState.id`, finds the matching `NSWindow` and closes it — keyed off a stable identifier set on each scene (e.g. tag each window via `WindowState.id` in a window accessor / `NSApplication.windows` lookup), rather than the current "can't map NSWindow" guesswork.
   Why: "Merge All Windows" needs a deterministic NSWindow→WindowState mapping to actually dismiss emptied windows (ISS-018); relying on SwiftUI to reconcile later is the bug.

- [x] 7. **ISS-018 — complete the Merge All Windows implementation**
   What: In `SputnikCommands.windowMenu`, after moving unique tabs into the target and calling `appState.closeWindow(id)`, call the step-6 helper to close each merged window's `NSWindow`; remove the empty placeholder loop and its apologetic comment.
   Why: Closes the orphaned native windows so the user is left with exactly one merged window (success condition).

- [x] 8. **ISS-019 — add a reorder mutator to WindowState**
   What: Add `func moveDocument(fromOffsets:toOffset:)` (or `moveDocument(id:before:)`) to `WindowState` (2.2) that reorders `openDocuments` in place without disturbing `activeDocumentID`.
   Why: Reordering is window-scoped document state and must live in `WindowState`, not the view (SR-1); keeping `activeDocumentID` stable preserves the selected tab across a drag.

- [x] 9. **ISS-019 — wire drag-to-reorder into DocumentTabBar**
   What: Add an `onDrag`/`onDrop` (or `.draggable`/`.dropDestination`) gesture to `TabItem`/`DocumentTabBar` that calls the step-8 mutator; use the session `id` as the drag payload and compute the target index from the drop location. Keep it SwiftUI-native (SW-3).
   Why: Provides the missing reorder interaction (ISS-019) while leaving the close/select callbacks untouched.

- [x] 10. **ISS-019 — verify reordered order persists**
   What: Confirm `AppState.collectDescriptors()` already serialises `openDocuments` order into `WindowDescriptor.openTabURLs`, and that `restoreWindows(from:)` re-opens them in that order; add nothing if it already does, otherwise adjust.
   Why: The success condition requires the new order to survive relaunch; persistence reads the live array order, so this is mostly a verification step.

- [x] 11. **Audit changed files for rule compliance**
   What: Re-scan every edited file for force-unwraps, retain cycles in new closures (`[weak self]` where escaping), and `@MainActor` correctness; confirm no module reaches into another's internals.
   Why: SR-2 / SW-1 / SW-2 / SR-1 must hold after the changes; the drag closures and the NSWindow lookup are the likeliest places to slip.

- [x] 12. **Build and manually verify all four success conditions**
   What: `swift build`, then exercise: new duplicate-free build, Merge All Windows, drag-reorder + relaunch, and move-dirty-tab prompt.
   Why: Each issue has a concrete observable outcome; confirm all four before closeout.

## Risks and Constraints
- **Foundation-wide change.** All four fixes are in module 2 (Foundation); per the skill this is flagged explicitly because Foundation changes can ripple to every other module. The edits are scoped to window/tab plumbing and shared UI, but the router and `WindowState` API additions must stay additive (no breaking signature changes to existing callers).
- **NSWindow↔WindowState mapping (ISS-018)** is the riskiest piece — SwiftUI's `WindowGroup` owns the `NSWindow` lifecycle, so the helper must locate windows without fighting SwiftUI. Prefer reading `NSApp.windows` and matching a tagged identifier set at scene creation; avoid force-closing windows SwiftUI still considers live.
- **Drag-and-drop in a `ScrollView` (ISS-019)** can interfere with horizontal scroll gestures; keep the drag threshold conservative and test with many tabs.
- **No third-party packages** (SR-5) and **modern concurrency only** (SW-1) — all new async work uses `async/await` on `@MainActor`.
- Plans are immutable once approved; if any step's scope grows, log a new issue/plan rather than editing this one.

## Files Affected
- `2 Foundation/2.6 App Lifecycle/SputnikApp.swift` — deleted (stale duplicate, ISS-017).
- `2 Foundation/Package.swift` — remove the now-unneeded `exclude` entry (ISS-017).
- `2 Foundation/2.1 Inter-Panel communication/AppInterPanelRouter.swift` — add dirty-aware `moveActiveTabToNewWindow()`; possibly a window-close helper (ISS-018, ISS-020).
- `2 Foundation/2.0 App Overview/SputnikCommands.swift` — repoint "Move Tab to New Window" at the router; complete "Merge All Windows" NSWindow closing (ISS-018, ISS-020).
- `2 Foundation/2.2 Global State Management/WindowState.swift` — add `moveDocument(...)` reorder mutator (ISS-019).
- `2 Foundation/2.4 UI and UX/DocumentTabBar.swift` — add drag-to-reorder gesture (ISS-019).
- `2 Foundation/2.2 Global State Management/AppState.swift` — possible window-close helper / verify descriptor order (ISS-018, ISS-019).
- Module Guides for 2.0, 2.1, 2.4, 2.6 — update where behaviour described changes.

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
- [x] Success Condition verified (ran / tested / confirmed as described above)
- [x] Module Guide(s) updated (`status` + `last_updated`)
- [x] Issues ISS-017–ISS-020 marked Resolved with date + resolution note
- [x] Changes committed: `[2 Foundation] Window & tab management fixes`
- [x] Pushed to GitHub
- [x] Plan moved to Plans Completed/
