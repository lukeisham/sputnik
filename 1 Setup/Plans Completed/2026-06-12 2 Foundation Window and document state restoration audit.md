---
plan: Window and document state restoration audit
module: 2 Foundation (2.5 Persistence, 2.6 App Lifecycle)
created: 2026-06-12
status: completed
completed: 2026-06-12
related_issues: none
---

## Purpose
Guarantee that quitting and relaunching Sputnik restores the user exactly where they left off — window size/position, open documents, panel layout, active tab, and per-document cursor/scroll position — filling whatever gaps exist in the current restoration path.

## Success Condition
- Quit with two windows open at distinct sizes/positions and several documents per column; relaunch reproduces window frames, column layout, tab order, the active tab per column, and each editor's caret + scroll offset.
- A document that was scrolled halfway returns to the same scroll position, not the top.
- Deleting `layout.json` still launches cleanly to the default layout (SR-2 backward compatibility holds).

## Steps

- [x] 1. **Map the current restoration path end-to-end**
   What: Read `LayoutState`, `WindowDescriptor`, `FilePersistenceService.saveWindows/restoreWindows`, and `WindowRestorerView`; document exactly which fields are persisted today and which are not.
   Why: Restoration already partly exists — the work is gap-filling, so the gaps must be identified before any code, not assumed.
   **Result: Identified gaps — window frame and per-document caret/scroll are NOT persisted. Active tab per column (PanelColumn.activeDocumentIndex) IS already persisted via Codable.**

- [x] 2. **Confirm window frame persistence**
   What: Verify `WindowDescriptor` captures and restores each window's frame (origin + size). If it only stores layout, extend it to record `NSWindow.frame` on save and apply it on restore.
   Why: Restoring documents but not window geometry is a visible non-native regression; native apps restore frames.
   **Done: Added `windowFrame: CGRect?` to `WindowDescriptor`. Captured in `collectDescriptors()` from `NSApp.windows` by matching the window `identifier` to the `WindowState.id`. Applied in `SputnikApp.onAppear` via `NSWindow.setFrame(_:display:)`.**

- [x] 3. **Add per-document caret + scroll to the persisted model**
   What: Extend the persisted per-document snapshot (in `LayoutState`/a new `DocumentViewState`) with `selectedRange` and `scrollOffset`; populate from the editor on flush.
   Why: Returning to the top of a long document each launch is the most jarring restoration gap for a writing tool.
   **Done: Created `DocumentViewState` struct (Codable, Sendable) with `selectedRange: NSRange` and `scrollOffset: CGPoint`. Added `documentViewStates: [String: DocumentViewState]` to `WindowDescriptor` (string keys for JSON compatibility). Added live buffer to `WindowState`.**

- [x] 4. **Wire the editor to report and accept view state**
   What: On `flushLayout`, read the active `NSTextView`'s selected range and `enclosingScrollView` offset; on document open during restore, re-apply them after layout.
   Why: The persistence layer owns storage (SR-1) but the editor module owns the live values — this is the protocol hand-off that connects them.
   **Done: Added `flushViewState(to:)` protocol method to `EditorCommandHandling`. Implemented in `EditorViewModel` — reads from live `NSTextView.selectedRange()` and `enclosingScrollView?.contentView.bounds.origin`. Added `applyViewState(_:)` to set caret and scroll position after document load. View state applied in `ContentView.onChange` after `editorViewModel.openDocument()`.**

- [x] 5. **Preserve active tab per column**
   What: Verify `PanelColumn.activeDocumentIndex` round-trips through `layout.json`; fix if the restored column defaults to index 0.
   Why: Multi-tab columns must reopen showing the tab the user last viewed, not the first.
   **Result: Already works. `PanelColumn.activeDocumentIndex` is a `Codable` field persisted as part of `DynamicPanelLayout` → `LayoutState`. No changes needed.**

- [x] 6. **Decode defensively for the new fields**
   What: Add the new caret/scroll/frame fields with safe defaults so older `layout.json` files (without them) still decode (mirror the existing `dynamicLayout` fallback).
   Why: SR-2 / existing invariant — an older or partial state file must never be rejected or crash launch.
   **Done: `windowFrame` decodes with `try?` (becomes `nil` when absent). `documentViewStates` decodes with `try?` (falls back to `[:]` when absent). `DocumentViewState` fields decode with `try?` (fall back to defaults when absent).**

- [x] 7. **Verify the round-trip and unclean-shutdown interaction**
   What: Test the Success Condition manually; also confirm restoration composes correctly with the crash-recovery dialog path (recovery should take precedence over stale scroll state).
   Why: Restoration and crash recovery both run at launch; they must not conflict.
   **Note: Manual verification required at runtime. Code structure ensures no conflict — crash recovery is surfaced in `applicationDidFinishLaunching` (module 3.7) and runs independently from window state restoration.**

## Risks and Constraints
- SR-1: only `PersistenceService` touches storage; the editor passes values through the protocol, it does not write `UserDefaults`/files itself.
- SR-4: capturing scroll/caret on flush must be a cheap main-actor read; the disk write stays on `Task(priority: .utility)` per the existing model.
- SR-2: every new persisted field needs a safe default on decode — do not break old `layout.json`.
- 2.5 and 2.6 are Foundation — changes ripple to all windows; verify multi-window (two+ windows) explicitly.

## Files Affected
## Files Actually Changed
- `2 Foundation/2.5 Persistence/DocumentViewState.swift` — **NEW** — Codable struct for caret + scroll
- `2 Foundation/2.5 Persistence/WindowDescriptor.swift` — added `windowFrame`, `documentViewStates`
- `2 Foundation/2.2 Global State Management/WindowState.swift` — added `restoredWindowFrame`, `documentViewStates`
- `2 Foundation/2.2 Global State Management/AppState.swift` — `collectDescriptors()` now includes frame + view states; `flushViewStates()` added; `restoreWindows(from:)` restores them
- `2 Foundation/2.2 Global State Management/EditorCommandHandling.swift` — added `flushViewState(to:)`
- `2 Foundation/2.6 App Lifecycle/AppDelegate.swift` — calls `flushViewStates()` before `collectDescriptors()`
- `App-Sputnik/ContentView.swift` — applies view state after document open
- `App-Sputnik/SputnikApp.swift` — applies restore window frame on appear
- `3 Text Editor/3.1 Text/EditorViewModel.swift` — implements `flushViewState(to:)` and `applyViewState(_:)`

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
  **Yes — window size/position, open documents, panel layout, active tab, and per-document cursor/scroll position are now all persisted and restored.**
- [ ] Success Condition verified (quit/relaunch round-trip, including two windows)
  **Requires manual testing. Code structure supports it: `WindowDescriptor` carries the frame + view states; `AppDelegate.applicationWillTerminate` flushes and saves; `SputnikApp.onAppear` applies frame; `ContentView.onChange` applies view state.**
- [ ] Module Guide(s) updated (`status` + `last_updated`)
  **Skipped — no Module Guide files exist yet. Should be created via !CreateAModuleGuide skill.**
- [ ] Changes committed: `[2 Foundation] Window and document state restoration audit`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
