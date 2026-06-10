---
plan: Wire the Text Editor document lifecycle and editor UI
module: 3 Text Editor
created: 2026-06-10
status: complete
related_issues: ISS-030, ISS-031, ISS-032, ISS-033, ISS-034, ISS-035, ISS-036, ISS-037, ISS-038, ISS-039, ISS-040, ISS-041 (unblocked: ISS-023–029 fixed in 7b13b5b)
flag: TOUCHES FOUNDATION (module 2.0 menu commands + 2.1 router). Save/Save As, "Render as HTML", and "ASCII Studio" are surfaced through Foundation menus that call a protocol the editor registers — Foundation must not call module-3 code directly (SR-1).
---

## Purpose
In order to make this module ready to build, connect module 3's already-implemented-but-unwired components into a logically functional document lifecycle and editor chrome, so opening a file actually loads it, protects against oversized/binary input, highlights syntax, watches for external changes, auto-saves/recovers, saves on demand, and exposes the mode picker, find bar, Render-as-HTML, and ASCII Studio the guides specify. 

## Success Condition
With the app building and running (see prerequisite), against a small `.md`, `.txt`, `.html`, and ASCII `.txt` file:
- Opening any document shows its **contents** in the editor (ISS-030).
- Opening a binary or oversized file is **refused** with a Sputnik alert; no RAM spike (ISS-031).
- Syntax highlighting renders for Markdown/HTML/ASCII, and is absent in plain text (ISS-032).
- Editing the file in another app raises the **reload-or-keep** prompt (ISS-033).
- **⌘F** slides in a working Find/Replace bar; Next/Prev/Replace/Replace-All operate (ISS-034).
- **⌘S / ⌘⇧S** write the buffer to disk; `isDirty` clears; the watcher does not self-trigger (ISS-035).
- Killing the app mid-edit and relaunching offers the **recovered** buffer (ISS-036).
- The **mode picker** is visible, auto-selects from the file extension, and switching it activates the matching 3.2/3.3/3.4 provider (ISS-037).
- A `<!DOCTYPE html>` file enables HTML suggestions + the Render-as-HTML item; a `.txt`/`.md` file enables live spell/grammar + quickfix (ISS-038, ISS-039).
- **⌘⌥P** opens the HTML Preview panel with the current file (ISS-040).
- **⌘⌥A** (Format → ASCII Studio) opens the Studio; Insert places ASCII at the cursor (ISS-041).

## Steps

- [x] 1. **Prerequisite gate — project must compile**
   What: Confirm the [Make project compile](../Plans New/2026-06-10 2 Foundation Make project compile.md) plan (ISS-023–029) has landed and `swift build` is clean before starting; do not begin until it is.
   Why: The app currently has ~30 Foundation compile errors, so none of this can be built, run, or verified until they are fixed.

- [x] 2. **Add the file-open pipeline to the editor view model**
   What: Add `func openDocument(_ url: URL?) async` to `EditorViewModel` (replacing the call site of `resetForNewFile`). It runs `EncodingGuard` on `Task(priority: .userInitiated)`; on success stores the decoded text in a new `loadedText` property and bumps a `loadToken: UUID`; infers `mode` from the file extension; runs `HTMLDocTypeGuard.check` and `SpellCheckFileTypeGuard` to set `htmlModeActive`/`spellCheckActive`; on failure sets no text and routes a `SputnikError` to `AppState` for alert presentation. Keep `resetForNewFile` as the flag-reset helper it calls internally.
   Why: One pipeline closes ISS-030 (load), ISS-031 (guard), ISS-037 (mode inference), ISS-038/039 (gating flags); centralising it in the view model honours SR-1 (module owns its state).

- [x] 3. **Inject the loaded text into the NSTextView**
   What: In `EditorView`, store the last-applied `loadToken` on the `Coordinator`; in `updateNSView`, when `viewModel.loadToken` differs, set `textView.string = viewModel.loadedText`, clear the undo stack, and run an initial highlight pass (Step 5). Guard against re-applying the same token to avoid clobbering edits.
   Why: `NSTextView` is created empty in `makeNSView`; this is the only correct seam to push freshly-loaded content across the `NSViewRepresentable` boundary (ISS-030).

- [x] 4. **Wire syntax highlighting**
   What: Invoke `SyntaxHighlighter` (a) once on load in Step 3 and (b) debounced from `Coordinator.textDidChange` via `DebounceTimer` (Foundation 2.7), keyed off `viewModel.mode`; skip entirely for `.plainText`. Run the pass on `Task(priority: .utility)` and write `NSTextStorage` attributes on `@MainActor`.
   Why: `SyntaxHighlighter` is implemented but never called (ISS-032); MR-3/SR-4 require the work off the main thread.

- [x] 5. **Construct a module-3 editor container and mount the find bar + mode picker**
   What: Add a SwiftUI `TextEditorPanel` (module 3) that stacks a toolbar row (a `Picker` bound to `editorViewModel.mode`), a `SearchBarView`, and `EditorView`. Expose the `SearchController` (already created in `makeNSView`) by assigning it onto `EditorViewModel.searchController` the same way `undoManager` is wired, so `SearchBarView` can bind to it and its `isVisible`/`searchTerm` drive the search. Replace the bare `EditorView(...)` in `ContentView` with `TextEditorPanel`, and change the `onChange(activeDocumentID)` handler to `Task { await editorViewModel.openDocument(appState.activeDocument?.url) }`.
   Why: The find UI is never mounted and there is no mode picker (ISS-034, ISS-037); editor chrome is module-3-specific UI so it belongs in module 3, not Foundation (SR-1, SW-3).

- [x] 6. **Trigger search on input and selection change**
   What: Call `SearchController.search()` when `searchTerm` changes (debounced) and on submit; ensure highlights clear when the bar hides. Confirm Next/Prev/Replace/Replace-All buttons in `SearchBarView` are wired to the controller methods.
   Why: The controller logic exists but nothing invokes `search()`; completes ISS-034.

- [x] 7. **Start the external file watcher per document**
   What: Instantiate `FileWatcher` (`NSFilePresenter`) for the open URL in Step 3's load path; on an external change, route a reload-or-keep prompt through `AppState` (Foundation alert). Re-target the watcher on each new document and stop it on close. Capture `self` weakly in the presenter callback (SW-2).
   Why: `FileWatcher` is never instantiated (ISS-033); MR-2 mandates `NSFilePresenter`, not polling.

- [x] 8. **Start auto-save / crash recovery**
   What: Instantiate `CrashRecoveryStore`; serialise the buffer to its temp cache on text change, debounced, on `Task(priority: .background)`, keyed by document identity. On `openDocument`, check for a newer recovery cache and offer to restore via an `AppState` prompt; clear the cache on a clean save.
   Why: `CrashRecoveryStore` is never instantiated (ISS-036); SR-4 keeps serialisation off the main thread.

- [ ] 9. **Implement Save / Save As — FOUNDATION TOUCH**
   What: Add `save() async` / `saveAs() async` to the editor (atomic write off-main, clear `isDirty`, suppress the watcher's own-write echo). Expose them via a small `EditorCommandHandling` protocol registered in Foundation (`AppState`/registry); add **⌘S / ⌘⇧S** items in `SputnikCommands` that call the registered handler — Foundation must not import module 3 (SR-1).
   Why: Save/Save As do not exist anywhere (ISS-035); the protocol indirection keeps Foundation an interface layer.

- [ ] 10. **Wire "Render as HTML" into the File menu — FOUNDATION TOUCH**
   What: Add a File-menu item (**⌘⌥P**) backed by `RenderAsHTMLCommand`, enabled only when `htmlModeActive`; it calls the 2.1 `InterPanelRouter` to open module 8 with the current file URL (bring-to-front + reload if already open).
   Why: `RenderAsHTMLCommand` is implemented but never added to the menu (ISS-040); routing through the 2.1 router respects SR-1.

- [ ] 11. **Wire the ASCII Studio trigger — FOUNDATION TOUCH + module 3**
   What: Add Format → **ASCII Studio** (**⌘⌥A**) that presents `ASCIIStudioPanel` for the active editor; wire its Insert action to `NSTextStorage` replacement at the cursor. Surface the menu item through Foundation, calling the editor handler from Step 9's protocol.
   Why: The Tier-2 Studio has no trigger (ISS-041); image-to-ASCII and the clip library are otherwise unreachable.

- [ ] 12. **Lifecycle + retain-cycle audit**
   What: On document close / app teardown, stop the `FileWatcher`, cancel the crash-recovery `Task`, flush a final save, and release the recovery cache handle. Audit every new escaping closure / long-lived `Task` for `[weak self]`.
   Why: Long-lived watchers and serialisation tasks holding strong `self` leak for the app's lifetime (SW-2, SR-3).

- [ ] 13. **Check and verify against the Success Condition; refresh guides**
   What: Logically check each bullet in the Success Condition with the four sample files. Then bump each affected sub-module guide's `last_updated` (and confirm `status` is accurate) for 3.1–3.5.
   Why: Closes the loop and keeps the guides truthful as the source of design intent.

## Risks and Constraints
- **Blocked by the compile plan (ISS-023–029).** Nothing here is verifiable until `swift build` is clean.
- **Foundation boundary (SR-1).** Menu commands (Save/Save As, Render as HTML, ASCII Studio) live in module 2.0 but must call a protocol the editor registers, not module-3 implementations directly; Foundation stays an interface layer.
- **NSViewRepresentable update loop.** Pushing text via `updateNSView` must be token-guarded so a SwiftUI re-render never re-applies stale content over live edits (Step 3).
- **Watcher self-write echo.** Save (Step 9) must suppress the `FileWatcher` notification it triggers, or every save will raise a false reload prompt.
- **No third-party packages (SR-5);** all of this uses AppKit/Foundation already present. No new force-unwraps (SR-2); modern concurrency only (SW-1).
- This plan does **not** alter the sub-module guides' design — they already describe the intended wiring; the code simply does not yet match them.

## Files Affected
- `3 Text Editor/3.1 Text/EditorViewModel.swift` — add `openDocument(_:) async`, `loadedText`, `loadToken`, `searchController` handle, save/recovery hooks.
- `3 Text Editor/3.1 Text/EditorView.swift` — token-guarded text injection; initial + debounced syntax highlight; assign `SearchController` to the view model; start watcher/recovery.
- `3 Text Editor/3.1 Text/TextEditorPanel.swift` — **new** SwiftUI container: mode picker + `SearchBarView` + `EditorView`.
- `3 Text Editor/3.1 Text/SearchBarView.swift` — bind to the lifted `SearchController`; trigger `search()` on input.
- `3 Text Editor/3.1 Text/EncodingGuard.swift`, `FileWatcher.swift`, `CrashRecoveryStore.swift`, `SyntaxHighlighter.swift` — now invoked (likely minor API shaping only).
- `3 Text Editor/3.4 HTML Langugage/HTMLDocTypeGuard.swift`, `RenderAsHTMLCommand.swift` — called from the open pipeline / File menu.
- `3 Text Editor/3.5 Spelling and Grammar Checking/SpellCheckFileTypeGuard.swift` — called from the open pipeline.
- `3 Text Editor/3.3 ASCII art/ASCIIStudioPanel.swift` — presented from the Format menu.
- `App-Sputnik/ContentView.swift` — host `TextEditorPanel`; call `openDocument` on `activeDocumentID` change.
- `2 Foundation/2.0 App Overview/SputnikCommands.swift` — Save/Save As, Render as HTML, ASCII Studio menu items (via registered protocol). **FOUNDATION TOUCH.**
- `2 Foundation/2.2 Global State Management/AppState.swift` (or registry) — register the `EditorCommandHandling` protocol + alert routing. **FOUNDATION TOUCH.**

## Progress Summary
- [x] Steps 1-8 complete (prerequisite, file-open pipeline, text injection, syntax highlighting, TextEditorPanel mounted, search debouncing, file watcher, crash recovery)
- [ ] Steps 9-13 pending (save/saveAs, menus, lifecycle audit, verification)

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`) for 3.1–3.5
- [ ] Changes committed: `[3 Text Editor] Wire document lifecycle and editor UI`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
