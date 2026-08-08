---
plan: 2 Foundation — Summary alignment and menu features
module: 2 Foundation (2.0 App Overview / 2.4 UI and UX)
created: 2026-06-16
status: complete
related_issues: ISS-140, ISS-141, ISS-142, ISS-143, ISS-144, ISS-145, ISS-146, ISS-147
---

## Purpose
Bring the codebase into sync with `2.0 Foundation_Summary_a.md` by implementing every menu item, keyboard shortcut, and feature shown in the summary — implementing three missing features (More-Context in Help menu, New File typed submenu, Supporting AI token count in the status bar), adding New Folder, and ensuring the code matches the specification exactly.

## Success Condition
- The codebase implements all menu items and shortcuts shown in `2.0 Foundation_Summary_a.md`.
- `Help > More Context ▶` is present and its per-language toggles write `WritingAssistMatrix` identically to those in Edit > Writing Assistance.
- `File > New File ▶` offers four typed options (.txt ⇧⌘T, .md ⇧⌘M, .html ⇧⌘H, .json ⇧⌘J); each creates an untitled document of the correct mode in the active window.
- `File > New Folder ⇧⌘F` creates a folder inside the active workspace directory; the item is disabled when no workspace directory is open.
- The status bar shows the Supporting AI token total (e.g. "claude-sonnet-4-6 · 4 312 tk") when `AppState.supportingAIUsage` is non-nil.
- `KeyboardShortcutCatalog` reflects every menu bar shortcut shown in the summary.
- `swift build` (all package targets) produces zero errors and zero warnings.

## Steps

- [ ] 1. **Add "More Context ▶" submenu to `HelpMenuGroup` (ISS-142)**
   What: In `HelpMenuGroup.swift`, add a `moreContextSubmenu` `@ViewBuilder` property modelled on `interactionSubmenu`. It should contain:
   - A `Menu` for each `WritingAssistLanguage` that has More Context support (Markdown, HTML, ASCII Art, JSON, Grammar).
   - After a Divider: `Button("All On")` and `Button("All Off")` for bulk control.
   - Insert `moreContextSubmenu` into `body` between the help topic buttons and `interactionSubmenu`, with a `Divider()` above.
   Why: The summary specifies this menu. More Context is discoverable from Help, parallel to Interaction.

- [ ] 2. **Implement "New File ▶" typed submenu in `FileMenuGroup` (ISS-143)**
   What:
   1. Add `func newTypedDocument(mode: EditorMode)` to `AppState`. It calls `newUntitledDocument()` and sets `activeDocument?.mode = mode` on the created session.
      - If SR-1 prevents importing `EditorMode` from module 3, add a `NewDocumentType` enum to Foundation 2.0 and map it to `EditorMode` when the document is loaded.
   2. In `FileMenuGroup`, replace `CommandGroup(replacing: .newItem)` with a `Menu("New File")` containing four typed options:
      - New Plain Text ⇧⌘T
      - New Markdown ⇧⌘M
      - New HTML ⇧⌘H
      - New JSON ⇧⌘J
   - Keep the standalone `New Tab ⌘T` button above it.
   3. Update `KeyboardShortcutCatalog` with all four new shortcuts.
   Why: The summary specifies these four options. Users expect typed-file creation in the File menu, per the spec.

- [ ] 3. **Implement "New Folder ⇧⌘F" in `FileMenuGroup` and `AppState` (ISS-143)**
   What:
   1. Add `func newFolder() async` to `AppState`:
      - Guard on `activeWindow?.activeWorkspaceDirectory`; return silently if nil.
      - Show an `NSAlert` with a text field for the folder name.
      - Validate (non-empty, no `/` characters); retry on invalid input.
      - Call `FileManager.default.createDirectory(at:withIntermediateDirectories:)`.
      - The FSEventStream watcher will fire automatically — no manual refresh needed.
   2. In `FileMenuGroup`, add below the New File menu:
      - Button("New Folder") calling `Task { await appState.newFolder() }`
      - Shortcut: ⇧⌘F
      - Disabled when no workspace is open.
   3. Update `KeyboardShortcutCatalog` with "New Folder ⇧⌘F".
   Why: The summary specifies this menu item. It's a basic file-browser operation users expect to find in File.

- [ ] 4. **Show Supporting AI token total in `StatusBarView` (ISS-144)**
   What: In `StatusBarView.body`, after the Supporting AI model name, append:
   ```swift
   if let usage = appState.supportingAIUsage, usage.totalTokensSinceLaunch > 0 {
       Text("· \(usage.totalTokensSinceLaunch.formatted()) tk")
           .font(.system(size: SputnikFont.caption, design: .monospaced))
           .foregroundStyle(SputnikColor.secondaryText)
           .lineLimit(1)
   }
   ```
   Why: The summary specifies "Token total (if loaded and since app launch)" in the status bar. It's already tracked; just needs wiring to the view.

- [ ] 5. **Update `KeyboardShortcutCatalog` to match the summary spec**
   What: Audit `KeyboardShortcutCatalog.swift` and ensure it includes:
   - All existing shortcuts (verify "Close Tab" = ⌘W, "New Window" = ⇧⌘N, etc.).
   - Four new typed New File shortcuts (⇧⌘T, ⇧⌘M, ⇧⌘H, ⇧⌘J).
   - "New Folder ⇧⌘F".
   Why: The catalog is the reference shown in Settings > Shortcuts. It must match the menu bar exactly per the summary spec.

- [ ] 6. **Update 2.0 Module Guide to match the implemented codebase**
    What: In `1 Setup/Module Guides/2 Foundation/2.0 App overview/guide.md`, update the Menu Bar ASCII diagram and "Sputnik-unique items" reference section to document what the code implements (matching the summary):
    - File menu includes "New File ▶" submenu with 4 typed options and "New Folder ⇧⌘F"
    - Edit menu correctly shows "Writing Assistance ▶" (not "Auto-complete")
    - View menu has correct shortcuts (⌥⌘2=Markdown Preview, ⌥⌘3=HTML Preview, ⌥⌘4=Terminal; Scratchpad=⇧⌘K) and the Focus Navigation section
    - Help menu includes "More Context ▶" alongside "Interaction ▶"
    - Status bar shows Supporting AI token total
    - Set `status: active`, `last_updated: 2026-06-16`.
    Why: The module guide documents what the module actually does. It must match the implemented codebase after this plan executes.

## Risks and Constraints
- **SR-1 (step 2):** `EditorMode` is defined in module 3; Foundation must not import module 3. Use a `NewDocumentType` enum in Foundation's 2.0 scope (parallel to `FileType` in 2.1), and map it to `EditorMode` inside the editor module when the document is first opened. Alternatively, `DocumentSession.mode` can accept a string/raw value set by Foundation and cast to `EditorMode` by module 3 on first access.
- **Shortcut conflicts (step 2):** Verify ⇧⌘M, ⇧⌘H, ⇧⌘J are unassigned before binding. Known shortcuts: ⇧⌘N (New Window), ⇧⌘S (Save As), ⇧⌘W (Close Window), ⇧⌘K (Scratchpad), ⇧⌘G (Find Previous), ⇧⌘Z (Redo). The four new ones appear clear.
- **`runModal()` on Main actor (step 3):** Safe to call from a Button action. The `Task { await appState.newFolder() }` pattern is correct.
- **`activeWorkspaceDirectory` nil check (step 3):** The menu item is disabled when no workspace is set; the `async` body should also guard at the start in case state changes between tap and execution.
- **Step 1 — `setWritingAssistAllMoreContext`:** Check if `SettingsStore` already has a bulk-set path before adding a new one. `setWritingAssistMatrix(.allOn())` enables all functions including moreContext, so "All On" can call that existing method.

## Files Affected
- `2 Foundation/2.0 App Overview/HelpMenuGroup.swift` — step 1 (More Context submenu)
- `2 Foundation/2.0 App Overview/FileMenuGroup.swift` — steps 2, 3 (New File submenu, New Folder)
- `2 Foundation/2.2 Global State Management/AppState.swift` — steps 2, 3 (newTypedDocument, newFolder methods)
- `2 Foundation/2.3 Settings/SettingsStore.swift` — step 1 (setWritingAssistAllMoreContext, if needed)
- `2 Foundation/2.4 UI and UX/StatusBarView.swift` — step 4 (token total display)
- `2 Foundation/2.0 App Overview/KeyboardShortcutCatalog.swift` — step 5 (new shortcuts)
- `1 Setup/Module Guides/2 Foundation/2.0 App overview/guide.md` — step 6 (guide update)

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified
- [ ] Module Guide 2.0 updated: `status: active`, `last_updated: 2026-06-16`
- [ ] Changes committed: `[2 Foundation] Summary alignment and menu features`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
