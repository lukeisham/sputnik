---
plan: Multi-tab document model and preview sync
module: 2 Foundation (2.2 / 2.1 / 2.4) + 8 HTML Preview
created: 2026-06-08
status: complete
related_issues: ISS-005, ISS-006
---

## Purpose
Replace the single-open-file model with a multi-document tab model so multiple files open as tabs in one editor panel, each preview panel renders whatever tab is active, and clicking a local link in the HTML preview opens its target as a new tab.

## Success Condition
- Opening a second file from the File Tree (or via a preview link) adds a tab to the editor's tab bar instead of replacing the current file.
- Selecting a tab switches the editor text **and** the Markdown/HTML preview together, with no preview ever showing a file that is not the active tab.
- Clicking a relative/local `.html` link in the HTML preview opens that file as a new active tab; clicking an `http(s)` link opens the system browser; an in-page `#anchor` scrolls the preview without changing tabs.
- Closing a tab with unsaved changes prompts via `SputnikAlert`; closing the last tab returns the editor and previews to an empty placeholder. No crash, no force-unwrap.

## Steps

- [ ] 1. **Define `DocumentSession` in Foundation 2.2**
   What: Add a `DocumentSession` type with a stable `id: UUID`, `url: URL?` (nil = untitled), `fileType: FileType`, `text: String` (or a reference to the editor's text storage), and `isDirty: Bool`. Make it `Identifiable` and `Sendable`-safe for read snapshots.
   Why: A per-file identity is the unit a tab and a preview both point at; a stable `UUID` lets the UI track tabs across reordering without relying on the URL (which can be nil or change on Save As).

- [ ] 2. **Add the open-documents collection to `AppState`**
   What: In `AppState` (2.2), add `openDocuments: [DocumentSession]` (ordered, drives the tab bar) and `activeDocumentID: UUID?`. Add a computed `activeDocument: DocumentSession?`. Keep `AppState` `@Observable @MainActor`.
   Why: `openDocuments` makes "what tabs exist" a single source of truth, and `activeDocumentID` makes "what is showing" a single source of truth — both editor and previews observe these, which is what removes the editor↔preview binding problem.

- [ ] 3. **Retire / redefine `currentlyOpenFile`**
   What: Replace `currentlyOpenFile` / `currentlyOpenFileType` with thin computed accessors derived from `activeDocument` (for backward-compatible reads), or remove them and migrate readers. Update the 2.2 guide's "State owned" list accordingly.
   Why: Closes ISS-005 — the single-file field cannot represent multiple tabs; leaving it as an independent writable field would create a second, divergent source of truth.

- [ ] 4. **Make `InterPanelRouter.open(_:)` find-or-create a session (2.1)**
   What: Change the router's `open(_ file: URL)` contract so it: (a) if a `DocumentSession` with that URL already exists, set it active and raise the panel; (b) otherwise create a session, append it to `openDocuments`, and set it active. Preview-vs-editor routing by `FileType` stays as today.
   Why: This is the one funnel every file-open path already uses (File Tree, "Render as HTML", and now preview links), so adding tab semantics here gives every caller tabs for free without each module knowing about tabs (SR-1).

- [ ] 5. **Add a `closeDocument(_:)` path through the router**
   What: Add `InterPanelRouter.close(_ id: UUID)` that removes the session, picks a sensible next `activeDocumentID` (neighbouring tab), and — if `isDirty` — raises a `SputnikAlert` confirm before discarding.
   Why: Tabs need a defined teardown; routing close through Foundation keeps lifecycle decisions (which tab becomes active, unsaved-changes prompt) in one place and prevents leaks (SW-2).

- [ ] 6. **Add the editor tab bar UI in Foundation 2.4**
   What: Define a `DocumentTabBar` SwiftUI view (and a `TabItem` row) as a shared UI/UX primitive, rendered at the top of the `.centerUpper` editor slot. It reads `openDocuments`, highlights `activeDocumentID`, writes selection via the router, and exposes a close button per tab. Add it to the 2.4 guide diagram + types.
   Why: "Tabs and Windows" (readme 2.4.2.5) currently has no backing UI; per SR-1 a tab bar shared across document types belongs in Foundation, not in the editor module.

- [ ] 7. **Bind the Text Editor (3) to the active session**
   What: Point the editor's `EditorViewModel` at `AppState.activeDocument` so switching tabs swaps the displayed text storage; persist each tab's undo stack / cursor with its `DocumentSession` (or note it as a follow-up if out of scope).
   Why: The editor must reflect the active tab for the model to be coherent; without this, tab switches would change previews but not the editor text.

- [ ] 8. **Bind the HTML Preview (8) to `activeDocumentID`**
   What: Implement `HTMLPreviewView` per the new Module 8 guide: render the active `.html` session, placeholder otherwise. No file-URL tracking inside the panel.
   Why: Makes the preview a pure function of the active tab — the core mechanism that keeps preview and editor in sync with zero extra wiring (closes the sync half of ISS-006).

- [ ] 9. **Implement `LinkNavigationPolicy` + `WKNavigationDelegate` (8)**
   What: Add `LinkNavigationPolicy.decide(for:targetIsBlank:workspace:)` and wire `HTMLPreviewCoordinator.decidePolicyFor`: in-page `#anchor` → `.allow`; local file → `.cancel` + `InterPanelRouter.open(url)`; `http(s)`/`target="_blank"` → `.cancel` + `NSWorkspace.shared.open(url)`; other schemes → `.cancel` + log.
   Why: A raw `WKWebView` navigates in place and desyncs from the editor (ISS-006); intercepting navigation is what turns a local link click into a new tab.

- [ ] 10. **Persist open tabs across launches (2.5)**
   What: Extend the persisted session state so `openDocuments` (URLs + active id) restore on launch, reusing the existing `PersistenceService`. Untitled/unsaved tabs follow the existing crash-recovery cache (module 3.7).
   Why: Tabs that vanish on relaunch break the "foundational" expectation; reusing PersistenceService keeps one persistence path (SR-1).

- [ ] 11. **Update affected Module Guides**
   What: Update 2.2 (DocumentSession + openDocuments/activeDocumentID, retire currentlyOpenFile), 2.1 (find-or-create open + close contract), 2.4 (DocumentTabBar). Bump `last_updated`; set 2.2/2.1 `status` per closeout. Module 8 guide already created.
   Why: Guides are the source of truth (SR-1, working conventions); leaving them stale would re-introduce the very ISS-005/006 gaps this plan closes.

## Risks and Constraints
- **Touches Foundation (module 2) — flagged per !GenerateAPlan rule.** Changes to `AppState` (2.2) and `InterPanelRouter` (2.1) affect every consuming module; the find-or-create change to `open(_:)` alters an existing contract, so every current caller (File Tree 6, "Render as HTML" 3.4) must be re-verified.
- ISS-001 (`PanelLayout` vs `LayoutState` naming) overlaps the persistence work in Step 10 — resolve or avoid colliding with it; do not silently pick one name.
- SR-3 / SR-2: each open tab holds text in memory — enforce the existing module-3 file-size guard per tab and avoid force-unwraps on `activeDocument` (always `guard let`).
- Markdown Preview (module 4) needs the same `activeDocumentID` binding and link policy, but its Module Guide does not exist yet — out of scope here; create it via `!CreateAModuleGuide` as a follow-up before wiring module 4.
- SW-2: `WKWebView` coordinator and any `AppState` observers must use `[weak self]` to avoid retaining the web view / view model.

## Files Affected
- `2 Foundation/AppState.swift` — add `openDocuments`, `activeDocumentID`, `activeDocument`; retire `currentlyOpenFile`.
- `2 Foundation/DocumentSession.swift` — new per-file session type (SR-6: own file).
- `2 Foundation/InterPanelRouter*.swift` — find-or-create `open(_:)`, new `close(_:)`.
- `2 Foundation/DocumentTabBar.swift` — new shared tab-bar UI primitive.
- `3 Text Editor Window/*` — bind `EditorViewModel` to `activeDocument`.
- `8 HTML Preview/HTMLPreviewView.swift`, `…/HTMLPreviewCoordinator.swift`, `…/LinkNavigationPolicy.swift` — new, per Module 8 guide.
- `2 Foundation/Persistence*` — persist/restore open tabs.
- Guides: `2.2`, `2.1`, `2.4` `guide.md` updated; `8 HTML Preview/guide.md` already created.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[2 Foundation] Multi-tab document model and preview sync`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
