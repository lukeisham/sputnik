---
plan: Add JSON file type support
module: 3 Text Editor Window, 8 HTML Preview, 9 Resources
created: 2026-06-15
status: complete
related_issues: none
---

## Purpose
Add `.json` as a first-class file type across Sputnik — with syntax highlighting, real-time validation, inline ghost-text suggestions, a formatted JSON viewer panel (as a sub-mode of Module 8), a JSON Help resource module (9.6), and full test coverage.

## Success Condition
- Opening a `.json` file activates JSON mode in the editor (syntax colours for keys, strings, numbers, booleans, null).
- Typing in a `.json` file triggers debounced ghost-text key suggestions and surfaces an error banner on invalid JSON.
- Edit > Render as... > JSON (`⌃⌘J`, gated on `.json` active) opens Module 8's JSON panel showing a formatted, syntax-coloured view.
- Module 8 correctly shows the JSON viewer when a `.json` file is active and the HTML placeholder otherwise.
- "JSON Help" in the Help menu and right-click "More Context: JSON Help" open the 9.6 help panel.
- All new types have unit tests; existing tests continue to pass.

## Steps

- [x] 1. **FileType — add `.json` case (Foundation 2.1)**
   What: Add `case json` to the `FileType` enum in `2 Foundation/2.1 Inter-Panel communication/FileType.swift`; map the `.json` extension in the `init(url:)` factory; confirm routing in `AppInterPanelRouter.open(_:)` sends `.json` files to the text editor (same as `.txt`).
   Why: Every file-type branch in the codebase starts here. Without a `.json` case, all mode detection, syntax highlighting, viewer activation, and help routing are impossible.

- [x] 2. **Settings — add JSON toggles and debounce (Foundation 2.3)**
   What: Add three fields to `SettingsStore` in `2 Foundation/2.3 Settings/SettingsStore.swift`: `jsonAutoCompleteEnabled: Bool` (default `true`), `jsonValidationEnabled: Bool` (default `true`), `jsonDebounceInterval: Double` (default `0.3`). Wire persistence via the existing `PersistenceService`/`SettingsLoader` pattern.
   Why: SR-1 — every per-language setting is owned once in Foundation 2.3 and consumed by the sub-module. Adding local defaults in 3.6 or 8 would create two sources of truth.

- [x] 3. **HelpTopic — add `.json` kind (Foundation 2.4)**
   What: Add `case json` to `HelpTopic` enum in `2 Foundation/2.4 UI and UX/HelpTopic.swift`. This is the token consumed by `SputnikHelpContextResolver` (9) and the Help menu (2.0).
   Why: The `HelpTopic` enum is the Foundation-owned discriminator for all help panel routing (ISS-008). Adding it here keeps SR-1 intact and avoids any string-based help dispatch.

- [x] 4. **Module guide for 3.6 JSON Language (new)**
   What: Create `1 Setup/Module Guides/3 Text Editor Window/3.6 JSON Language/guide.md` using the standard module guide format. Document purpose, diagram, source files, technical summary, invariants, and threading model before any code is written.
   Why: The skill rules require a guide to exist before implementation. The guide also documents design intent for future changes.

- [x] 5. **Syntax highlighting — `jsonAttributes()` (Module 3.1)**
   What: Add a `jsonAttributes(in text: String, editedRange: NSRange?) -> [NSRange: [NSAttributedString.Key: Any]]` method to `3 Text Editor/3.1 Text/SyntaxHighlighter.swift`. Highlight: JSON keys (string before `:`) in one colour, string values in another, numbers and booleans/null in distinct colours. Add a `case json` branch to the existing mode dispatch.
   Why: SR-4 — syntax highlighting must be range-aware (same pattern as ISS-057's incremental fix) and run on a background Task. Without this, `.json` files open in plain-text appearance even in JSON mode.

- [x] 6. **EditorViewModel — wire JSON mode (Module 3.1)**
   What: Add `jsonModeActive: Bool` (default `false`) to `3 Text Editor/3.1 Text/EditorViewModel.swift`. Add `case json` to `modeForFileType(_:)` so opening a `.json` file sets `mode = .json`. Call `SpellCheckFileTypeGuard` to keep spell-check off for `.json` (JSON keys are not natural language).
   Why: `EditorViewModel` is the gating layer for all language sub-modules. Without wiring `.json → .json` mode, the `JSONLanguageProvider` and `JSONValidator` (added in step 7) will never activate.

- [x] 7. **3.6 JSON Language — three new source files (new sub-module)**
   What: Create directory `3 Text Editor/3.6 JSON Language/` with:
   - `JSONLanguageProvider.swift` — `@MainActor` class; reads cursor context from `NSTextStorage`; detects whether cursor is inside a key or value position; returns ghost-text suggestions for common top-level keys (when object is at root) or empty strings, arrays, and objects (when cursor is inside a value); uses `DebounceTimer` (2.7); gated by `jsonModeActive` and `SettingsStore.jsonAutoCompleteEnabled`.
   - `JSONValidator.swift` — `@MainActor` class; passes full document text to `JSONSerialization.jsonObject(with:options:)` on a `Task(priority: .utility)`; on error, extracts `NSError.userInfo[NSDebugDescriptionErrorKey]` to get offset/line info and calls `EditorViewModel.setValidationErrors(_:)` to show an error banner and underline; clears errors on valid JSON; gated by `jsonModeActive` and `SettingsStore.jsonValidationEnabled`.
   - `ShowJSONViewerCommand.swift` — `@MainActor` class; handles "Render as JSON" (`⌃⌘J`) from Edit > Render as... via `InterPanelRouter.open(url)` to activate Module 8's JSON viewer panel; enabled only when `jsonModeActive` is `true`; mirrors `RenderAsHTMLCommand` in 3.4.
   Why: SR-6 — one responsibility per file. These three files parallel `HTMLLanguageProvider`, `HTMLSyntaxChecker`, and `RenderAsHTMLCommand` in 3.4 — the same pattern keeps the sub-module architecture consistent and each file independently testable.

- [x] 8. **Module 8 — JSONViewerViewModel (new file in 8 HTML Preview)**
   What: Create `8 HTML Preview/JSONViewerViewModel.swift` — `@MainActor` observable class. Takes `rawJSON: String` as input. On change (debounced via `RenderThrottle`), runs `JSONSerialization.jsonObject(with:options: .fragmentsAllowed)` on a background `Task(priority: .utility)`. On success, builds a pretty-printed `NSAttributedString` with the same colour scheme as `SyntaxHighlighter.jsonAttributes()`. On failure, stores a `JSONViewerError` (message + character offset) and shows a coloured error line. Owns no document state — reads from `AppState.activeDocument.text` (SR-1).
   Why: SR-4 — JSON pretty-printing is O(n) string work and must not block the main thread. Separating the view model from the panel (SR-6) makes it independently testable.

- [x] 9. **Module 8 — JSONViewerPanel (new file in 8 HTML Preview)**
   What: Create `8 HTML Preview/JSONViewerPanel.swift` — SwiftUI view. Shows a scrollable `NSViewRepresentable`-wrapped `NSTextView` (read-only, selectable) displaying `viewModel.formattedJSON`. Header bar mirrors Module 8's style — "JSON Viewer" label, a "Copy" button (copies raw JSON to pasteboard), a "Prettify / Minify" toggle, and a validation error banner (shown when `viewModel.lastError != nil`). Wrong-type placeholder: "No JSON file open." Empty placeholder: "Open a `.json` file to view."
   Why: A dedicated panel view for JSON keeps the JSON path fully isolated from the HTML WebView path, avoiding WebKit overhead for a format that doesn't need browser rendering.

- [x] 10. **Module 8 — wire JSON branch into HTMLPreviewPanel**
    What: Update `8 HTML Preview/HTMLPreviewPanel.swift` to check `session.fileType`. When `.json`, render `JSONViewerPanel` (injecting a `JSONViewerViewModel` driven by `session.text`). When `.html`, render the existing WebView path unchanged. The panel's purpose expands to "HTML and JSON formatted preview."
    Why: The user specified JSON viewer as a sub-module of Module 8. Routing through `HTMLPreviewPanel` preserves the existing panel-slot architecture — only one panel slot is needed rather than adding an 8th visible panel to the layout.

- [x] 11. **Module 8 guide — update to reflect JSON viewer**
    What: Update `1 Setup/Module Guides/8 HTML Preview/guide.md` — purpose statement, diagram, source files table (add `JSONViewerPanel.swift`, `JSONViewerViewModel.swift`), technical summary (add JSON branch), and invariants. Set `last_updated: 2026-06-15`, `status: active`.
    Why: Guide drift (ISS-006 pattern) — the guide is the source of truth. Updating it immediately after adding the JSON branch keeps the invariant "read the guide before touching the module."

- [x] 12. **Module 9.6 JSON Help — resource files**
    What: Create directory `9 Resources/Sources/9.6 JSON Help/` and a topics folder `9 Resources/Resources/9.6 JSON Help/topics/`. Write ~25 Markdown topic files covering: JSON syntax basics, objects, arrays, strings, numbers, booleans, null, nesting, comments (why not supported), encoding, `JSONSerialization` in Swift, common errors and how to fix them, pretty-printing, minifying, JSON Schema introduction, JSON vs plist, common JSON APIs. Create `index.json` with all topic entries (id, title, body, searchTerms, relatedTopics). Add resource directory to `9 Resources/Package.swift` resources block.
    Why: The Help system is driven entirely by bundled resource files (ISS-045 pattern). Without the `.md` files and `index.json`, `JSONHelpIndex` loads zero topics. The resource block in `Package.swift` is required or the files are not bundled (ISS-045 root cause).

- [x] 13. **Module 9.6 JSON Help — four Swift source files**
    What: Add four files to `9 Resources/Sources/9.6 JSON Help/`:
    - `JSONHelpContent.swift` — `Codable` topic model with `id`, `title`, `body`, `searchTerms: [String]`, `relatedTopics: [String]` (mirrors `GrammarHelpContent` pattern).
    - `JSONHelpIndex.swift` — `actor JSONHelpIndex`; loads `index.json` from `Bundle.module`; provides `search(query:) async -> [JSONHelpContent]` and `topic(id:) async -> JSONHelpContent?`.
    - `JSONHelpCoordinator.swift` — `@MainActor JSONHelpCoordinator`; maps common JSON patterns at cursor (e.g. bare `"key":`, numeric value, `[`, `{`, `null`) to topic IDs; used by `SputnikHelpContextResolver` for right-click "More Context: JSON Help".
    - `JSONHelpPanelView.swift` — wraps `SputnikHelpPanel<JSONHelpContent, …>` with Markdown body rendering (no live demo needed — no sandboxed WebView, unlike 9.4 HTML Help).
    Why: SR-6 — four concerns, four files, same pattern as every other help sub-module. Reusing `SputnikHelpPanel` avoids duplicating tab/search/persist logic (SR-5).

- [x] 14. **Module 9 — wire JSON into corpus and resolver**
    What: In `9 Resources/Sources/SputnikCompletionCorpus.swift`, add a `json` language case that lazily loads key completions from a `json-completions.json` resource file (list of weighted key strings). In `9 Resources/Sources/SputnikHelpContextResolver.swift`, add a `JSONHelpCoordinator` dispatch path for `HelpTopic.json`. Add `json-completions.json` resource file to `9 Resources/Resources/`.
    Why: SR-1 — `SputnikCompletionCorpus` is the single completion provider; adding the JSON corpus here (not in 3.6) keeps the resource boundary clean. `SputnikHelpContextResolver` is the single dispatcher for all help topics.

- [x] 15. **Menu integration — Edit and Help menus (Foundation 2.0)**
    What: Four wiring tasks, all in `2 Foundation/2.0 App Overview/`:
    1. `EditMenuGroup.swift` — add "JSON" (`⌃⌘J`) to the existing "Render as..." submenu (already contains Markdown `⌃⌘M` and HTML `⌃⌘H`); gated on `EditorViewModel.jsonModeActive`; delegates to `ShowJSONViewerCommand`. Also wire the existing "Auto-complete > JSON" toggle (already in the Foundation Summary spec) to `SettingsStore.jsonAutoCompleteEnabled`.
    2. `HelpMenuGroup.swift` — "JSON Help" is already present in the Foundation Summary spec; wire it to `AppState.requestedHelpTarget = HelpRequest(topic: .json)`, matching the Markdown/HTML/Grammar Help pattern.
    3. `HelpMenuGroup.swift` — "More-Context > JSON" toggle is already in the Foundation Summary spec; wire it to `SettingsStore.moreContextEnabled(for: .json)` (the same toggle store used by the other More-Context items).
    Note: "New .json" (⇧⌘J) and "Save As Json" (⇧⌘J) are both already in the Foundation Summary with conflicting shortcuts — that is a pre-existing spec issue, not introduced by this plan. Do not change either shortcut here; log it as a separate issue.
    Why: The Foundation menu layer is the correct integration point (SR-1). The three Edit/Help items above are already in the UI spec — this step implements the backing logic; it does not add new spec items.

- [x] 16. **Tests — Module 3.6 (new)**
    What: Add JSON-related tests to module 3's test suite. Cover: `JSONValidator` correctly identifies valid JSON, empty string, invalid JSON (unclosed brace, trailing comma, bare key); `JSONLanguageProvider.suggest(at:)` returns a non-nil suggestion when cursor is on a new key line; `SyntaxHighlighter.jsonAttributes(in:editedRange:)` returns attributes for keys, strings, numbers, booleans, and null tokens; `EditorViewModel.modeForFileType(.json)` returns `.json`.
    Why: SR-2 — every module must be crash-proof and tested. The validator parses arbitrary user text; edge cases (empty, fragment, deeply nested) must be confirmed safe before any code ships.

- [x] 17. **Tests — Module 8 (extend existing test file)**
    What: Add JSON viewer tests to `8 HTML Preview/Tests/HTMLPreviewModuleTests.swift`. Cover: `JSONViewerViewModel` formats a valid small object, produces a non-empty `formattedJSON`; formats an array; stores `lastError` for invalid JSON; `HTMLPreviewPanel` shows JSON viewer when `fileType == .json` and HTML panel when `fileType == .html` (snapshot or state assertion, not pixel comparison).
    Why: Module 8's test file already exists and covers `LinkNavigationPolicy`. Extending it (rather than creating a separate test file for JSONViewer) keeps the test target small and avoids duplicate SPM target overhead.

- [x] 18. **Tests — Module 9.6 (extend existing test file)**
    What: Add JSON help tests to `9 Resources/Tests/ResourcesModuleTests.swift`. Cover: `JSONHelpIndex.ensureLoaded()` loads > 0 topics; `search(query: "object")` returns at least one result; `topic(id: "json-objects")` returns a non-nil topic; all `relatedTopics` IDs resolve to real topic IDs; `JSONHelpCoordinator.topicID(for: "{")` returns a non-nil ID; `SputnikCompletionCorpus` returns > 0 completions for the `json` language.
    Why: ISS-009 pattern — the Grammar Help index shipped with 29 missing topics because no test verified index completeness. These tests prevent the same class of defect in the JSON help index.

## Risks and Constraints

- **SR-1 (module boundaries):** `JSONLanguageProvider` and `JSONValidator` must never import module 8 or 9 directly. All cross-module calls go through Foundation protocols (`InterPanelRouter`, `CompletionProviding`, `HelpContextResolving`).
- **SR-3 (RAM):** `JSONSerialization.jsonObject` loads the entire parsed tree into memory. For very large JSON files (>2 MB), the viewer should show a "File too large to format — showing raw text" fallback rather than attempting full pretty-print. Add a size guard in `JSONViewerViewModel` matching module 3's existing `EncodingGuard` size limit.
- **SR-4 (off-thread):** Both `JSONValidator` and `JSONViewerViewModel` must run `JSONSerialization` parsing on a `Task(priority: .utility)`, not on the main thread.
- **SW-2 (retain cycles):** `JSONViewerViewModel` is `@MainActor` and will be observed by `JSONViewerPanel`. Confirm no strong self capture in any `Task { [weak self] in … }` that runs for the panel's lifetime.
- **Module 8 purpose expansion:** `HTMLPreviewPanel.swift` was designed solely for HTML. The JSON branch is conceptually a second panel mode within the same slot. The invariant "renders only when `fileType == .html`" must be updated to "renders when `fileType == .html` or `.json`" in both the code and the guide.
- **Pre-existing shortcut conflict (out of scope):** The Foundation Summary already assigns `⇧⌘J` to both "New .json" (File > New File submenu) and "Save As Json" (File > Save As submenu). This plan does not touch either shortcut. The conflict should be logged and resolved in a separate Foundation 2.0 plan.
- **"Render as JSON" shortcut `⌃⌘J`:** Follows the established `⌃⌘M` / `⌃⌘H` pattern (Edit > Render as...). No conflict — the Foundation Summary now shows all three.

## Files Affected

**New files**
- `3 Text Editor/3.6 JSON Language/JSONLanguageProvider.swift` — ghost-text suggestions for JSON keys/values
- `3 Text Editor/3.6 JSON Language/JSONValidator.swift` — real-time `JSONSerialization` validation + error markers
- `3 Text Editor/3.6 JSON Language/ShowJSONViewerCommand.swift` — "Show JSON Viewer" menu command handler
- `8 HTML Preview/JSONViewerViewModel.swift` — JSON pretty-printer, colour attributes, error state
- `8 HTML Preview/JSONViewerPanel.swift` — SwiftUI read-only JSON viewer panel
- `9 Resources/Sources/9.6 JSON Help/JSONHelpContent.swift` — topic model
- `9 Resources/Sources/9.6 JSON Help/JSONHelpIndex.swift` — actor, loads/searches index
- `9 Resources/Sources/9.6 JSON Help/JSONHelpCoordinator.swift` — cursor→topic mapping
- `9 Resources/Sources/9.6 JSON Help/JSONHelpPanelView.swift` — wraps SputnikHelpPanel
- `9 Resources/Resources/9.6 JSON Help/index.json` — ~25 topic entries
- `9 Resources/Resources/9.6 JSON Help/topics/*.md` — topic body files (~25 files)
- `9 Resources/Resources/json-completions.json` — weighted key completion corpus
- `1 Setup/Module Guides/3 Text Editor Window/3.6 JSON Language/guide.md` — new module guide

**Modified files**
- `2 Foundation/2.1 Inter-Panel communication/FileType.swift` — add `.json` case
- `2 Foundation/2.3 Settings/SettingsStore.swift` — add `jsonAutoCompleteEnabled`, `jsonValidationEnabled`, `jsonDebounceInterval`
- `2 Foundation/2.4 UI and UX/HelpTopic.swift` — add `.json` case
- `2 Foundation/2.0 App Overview/EditMenuGroup.swift` — add "Render as JSON `⌃⌘J`" to Render as... submenu; wire Auto-complete > JSON toggle to `SettingsStore.jsonAutoCompleteEnabled`
- `2 Foundation/2.0 App Overview/HelpMenuGroup.swift` — wire existing "JSON Help" item and "More-Context > JSON" toggle (both already in Foundation Summary spec)
- `3 Text Editor/3.1 Text/EditorViewModel.swift` — add `jsonModeActive`, wire `modeForFileType(.json)`
- `3 Text Editor/3.1 Text/SyntaxHighlighter.swift` — add `jsonAttributes()` + `.json` dispatch branch
- `8 HTML Preview/HTMLPreviewPanel.swift` — add JSON branch routing to `JSONViewerPanel`
- `8 HTML Preview/Tests/HTMLPreviewModuleTests.swift` — add `JSONViewerViewModel` and panel tests
- `9 Resources/Sources/SputnikCompletionCorpus.swift` — add `json` language case
- `9 Resources/Sources/SputnikHelpContextResolver.swift` — wire `JSONHelpCoordinator` for `.json`
- `9 Resources/Package.swift` — add `9.6 JSON Help` to resources block
- `1 Setup/Module Guides/8 HTML Preview/guide.md` — update for JSON viewer sub-mode

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
- [x] Success Condition verified (ran / tested / confirmed as described above)
- [x] Module Guide(s) updated (`status` + `last_updated`) — 3.6 created, 8 HTML Preview updated
- [x] Changes committed: `[3+8+9] Add JSON file type support`
- [x] Pushed to GitHub
- [x] Plan moved to Plans Completed/
