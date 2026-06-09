---
plan: More Context shared lookup utility
module: 2 Foundation (2.7 Utilities) + 3 Text Editor, 4 Markdown Preview, 8 HTML Preview, 9 Resources
created: 2026-06-09
status: pending
related_issues: ISS-008 (open, related), ISS-010 (open, this plan fixes)
---

## Purpose
Promote the select-and-right-click "More Context" help-lookup gesture out of the Text Editor into a single reusable Foundation 2.7 utility, then wire it into the Markdown Preview (Grammar + Markdown help) and HTML Preview (Grammar + HTML help) so every panel that shows authored text can open the matching help — without duplicating logic.

## Success Condition
- In the Text Editor, selecting a word and right-clicking still shows a "More Context: <Help>" item that opens the correct help panel/topic (behaviour unchanged for the user, now driven by the shared utility).
- In the **Markdown Preview**, selecting text and right-clicking shows **two** items — "More Context: Grammar Help" and "More Context: Markdown Help" — each opening the relevant panel to the matched topic.
- In the **HTML Preview**, selecting text and right-clicking shows **two** items — "More Context: Grammar Help" and "More Context: HTML Help" — each opening the relevant panel to the matched topic.
- Foundation imports no module-9 type (verified by inspection); the concrete coordinator dispatch lives entirely in module 9.
- No force-unwraps; `[weak self]` in every escaping closure on long-lived views; builds clean under Swift 6 strict concurrency.

## Architectural decision (SR-1)
Per SR-1, Foundation is an **interface layer, not an orchestration layer**. Therefore:
- **Foundation 2.7** owns only content-agnostic plumbing: the resolver *protocol*, a small query value type, a closure-bridging menu item, and a menu-item builder that turns a selection + candidate `HelpTopic` kinds into `NSMenuItem`s and routes the result through a caller-supplied sink. Foundation never references `GrammarHelpCoordinator` et al.
- **Module 9 (Resources)** owns the one concrete resolver that knows the coordinators (the logic currently in `EditorTextView.resolveTopicID`). This is the orchestration, and it stays out of Foundation.
- **Hosts** (Editor 3.1, Markdown Preview 4, HTML Preview 8) each supply their own candidate kinds and selected-text extraction, and call the shared builder.

## Steps

1. **Foundation 2.7 — define the resolver protocol + query type**
   What: Add `HelpContextResolving` (a `Sendable` protocol with `func resolve(_ query: HelpContextQuery) async -> HelpRequest?`) and `HelpContextQuery` (`Sendable` value type: `kind: HelpTopic`, `selectedText: String`, `fullText: String`, `cursorOffset: Int`). New files under `2 Foundation/2.7 Utilities/`.
   Why: Gives Foundation a typed seam for "resolve a selection to a `HelpRequest`" without knowing any concrete help module (SR-1). `HelpRequest`/`HelpTopic` already live in Foundation 2.4, so no new cross-module type is introduced.

2. **Foundation 2.7 — add a closure-bridging menu item**
   What: Add `ClosureMenuItem`, a tiny `@MainActor NSMenuItem` subclass that runs a stored `() -> Void` on activation (its own `target`/`action`). New file.
   Why: Lets the builder create self-contained menu items without each host wiring `@objc` selectors; a genuinely general-purpose utility (fits 2.7's remit, SR-6 one responsibility).

3. **Foundation 2.7 — add the More Context menu builder**
   What: Add `MoreContextMenu` (a `@MainActor` enum) with `items(forSelectedText:kinds:fullText:cursorOffset:resolver:onRequest:) -> [NSMenuItem]`. For each candidate `HelpTopic` it builds one `ClosureMenuItem` titled `"More Context: <kind.title>"`; on activation it `Task`s `resolver.resolve(query)` then calls `onRequest(request)` on the result. Returns `[]` when the selection is empty/whitespace.
   Why: This is the shared gesture plumbing all three hosts reuse; "two flat items" is satisfied by returning one item per kind. Routing is delegated to the host's `onRequest` sink (which writes `AppState.requestedHelpTarget`), keeping Foundation free of `AppState`-mutation glue at the call site.

4. **Module 9 — implement the concrete resolver**
   What: Add `SputnikHelpContextResolver: HelpContextResolving` in `9 Resources/` (e.g. `SputnikHelpContextResolver.swift`). Move the body of `EditorTextView.resolveTopicID(kind:selected:fullText:cursorOffset:)` here, switching on `query.kind`: `.grammar` → `GrammarHelpCoordinator.shared.lookup`; `.markdown` → `MarkdownHelpCoordinator.shared.lookupContext`; `.html` → `HTMLHelpCoordinator.shared.lookupContext`; `.asciiArt` → `ASCIIArtHelpCoordinator.shared.bestMatch`; `.sputnik` → `nil`. Return `HelpRequest(kind:topicID:)`.
   Why: Keeps coordinator dispatch in the module that owns the coordinators (SR-1). One resolver serves all hosts, so no logic is duplicated.

5. **Module 9 — extend `GrammarHelpSource` for HTML preview**
   What: Add `case htmlPreview` to `GrammarHelpSource` in `GrammarHelpCoordinator.swift`. The resolver passes the source through for grammar lookups; previews pass `.markdownPreview` / `.htmlPreview`, editor passes `.editor`.
   Why: Grammar Help is the one dual/tri-source panel; recording the source keeps the existing source-tagged result contract intact while admitting the new HTML-preview origin.

6. **Text Editor 3.1 — refactor `EditorTextView` onto the shared builder**
   What: In `menu(for:)`, after computing `helpKind(for:)`, replace the hand-rolled `NSMenuItem` + `lookUpHelp(_:)` + static `resolveTopicID` with a call to `MoreContextMenu.items(...)`, passing `[kind]`, the selection, full text, cursor offset, the shared resolver, and the existing `onRequestHelp` sink. Delete `lookUpHelp(_:)` and `resolveTopicID(...)`.
   Why: Single source of truth; the editor keeps its mode-driven single-kind policy while the gesture/resolution code is shared (the chosen "refactor editor too" path).

7. **Markdown Preview 4 — capture selection + add the gesture**
   What: Subclass the preview `NSTextView` (or add a `menu(for:)` override via the existing view) to append `MoreContextMenu.items(...)` with kinds `[.grammar, .markdown]`, using the text view's `selectedRange`/`string` for selected text + cursor offset. Add an `onRequestHelp` sink wired in `MarkdownRenderView`/`MarkdownPreviewPanel` to set `AppState.requestedHelpTarget` (capture `appState` weakly, SW-2).
   Why: Markdown Preview is an `NSTextView` host, so selection extraction is native and mirrors the editor; this delivers the two required preview items.

8. **HTML Preview 8 — migrate JS policy + capture selection (ISS-010)**
   What: Replace `configuration.preferences.javaScriptEnabled = false` with `configuration.defaultWebpagePreferences.allowsContentJavaScript = false` (disables author scripts). Inject an app-owned `WKUserScript` + register a `WKScriptMessageHandler` that posts `window.getSelection().toString()` on `selectionchange`; cache it on `HTMLPreviewCoordinator`. Subclass `WKWebView` to override `willOpenMenu(_:with:)`, appending `MoreContextMenu.items(...)` with kinds `[.grammar, .html]` using the cached selection (full text = active session text, cursorOffset = 0). Wire an `onRequestHelp` sink as in step 7.
   Why: Resolves ISS-010 — page JS stays off for safety while the app can still read the selection; delivers the two required HTML-preview items. Use the message handler's `add(_:name:)`/`removeScriptMessageHandler` carefully to avoid a retain cycle on the coordinator (SW-2).

9. **App assembly — provide the resolver to each host**
   What: Inject a shared `SputnikHelpContextResolver` instance into the three hosts at construction (alongside the existing router/appState wiring in `EditorView`, `MarkdownPreviewPanel`/`MarkdownRenderView`, `HTMLPreviewView`/`HTMLPreviewPanel`).
   Why: Hosts depend on the Foundation protocol, not the concrete module-9 type at the call site beyond construction, keeping the dependency direction correct.

10. **Update module guides**
    What: 2.7 — add the More Context utility (`HelpContextResolving`, `HelpContextQuery`, `ClosureMenuItem`, `MoreContextMenu`) to Key types + Known consumers (3.1, 4, 8). 4 Markdown Preview — document the More Context right-click (Grammar + Markdown). 8 HTML Preview — document the More Context right-click (Grammar + HTML) and the JS-policy change. 9.5 Grammar Help — extend Mode 3 to cover both Markdown **and** HTML preview as lookup sources and note the shared utility. Set `last_updated: 2026-06-09` on each.
    Why: Guides are the source of truth; the feature changes the design intent of four modules.

11. **Verify**
    What: Build; manually confirm all three hosts show the correct items and open the right panel/topic; confirm Foundation has no `import`/reference to module-9 types; confirm editor behaviour is unchanged.
    Why: Matches the Success Condition.

12. **Commit and push to GitHub**
    What:
    1. Run `git status --short` to confirm no unrelated uncommitted changes are mixed in. If present, stash them with `git stash push -m "unrelated pre-plan changes"` before proceeding.
    2. Run `git --no-pager log origin/main..HEAD` to check whether there are pre-existing unpushed commits from prior work. If there are, note that `git push origin main` will include them alongside this plan's commit — confirm with the team or leave them unmentioned; the key is awareness.
    3. Stage only the files listed in **Files Affected** (and nothing else): `git add <each file path>`.
    4. Commit with the conventional format message: `git commit -m "[2 Foundation] More Context shared lookup utility"`.
    5. Push to `main` on GitHub: `git push origin main`.
    Why: Ensures the feature is version-controlled and available to collaborators; guards against accidentally committing unrelated work; makes the push's scope transparent; satisfies the project's closeout requirement of pushing all changes to GitHub.

## Risks and Constraints
- **Foundation change (flagged):** module 2 changes ripple to every consumer. Mitigated by keeping 2.7 additions purely additive interface/plumbing — no edits to existing 2.7 types, no Foundation→module-9 dependency.
- **HTML selection capture (primary risk, ISS-010):** if app-injected `WKUserScript` cannot read the selection with `allowsContentJavaScript = false`, fall back to a dedicated `WKContentWorld`/`evaluateJavaScript(in:)` for the selection query, or gate HTML-preview More Context behind a setting. Resolve during step 8 before wiring the rest.
- **`willOpenMenu` is synchronous** — selection must be cached ahead of time (selectionchange handler), not fetched on menu open.
- **Retain cycles (SW-2):** `WKScriptMessageHandler` registration and the `onRequestHelp` closures must capture weakly; audit each touched file after the refactor.
- **ISS-008 overlap:** this plan routes all three hosts through `AppState.requestedHelpTarget`, reinforcing the single Foundation route ISS-008 calls for; it does not itself close ISS-008 (the coordinators' divergent `openHelp` paths remain).

## Files Affected
- `2 Foundation/2.7 Utilities/HelpContextResolving.swift` — new: resolver protocol + `HelpContextQuery`.
- `2 Foundation/2.7 Utilities/ClosureMenuItem.swift` — new: closure-bridging `NSMenuItem`.
- `2 Foundation/2.7 Utilities/MoreContextMenu.swift` — new: menu-item builder.
- `9 Resources/SputnikHelpContextResolver.swift` — new: concrete resolver (moved dispatch).
- `9 Resources/9.5 Grammar Help/GrammarHelpCoordinator.swift` — add `.htmlPreview` source.
- `3 Text Editor/3.1 Text/EditorTextView.swift` — use builder; delete `lookUpHelp`/`resolveTopicID`.
- `4 Markdown Preview/MarkdownRenderView.swift` (+ `MarkdownPreviewPanel.swift`) — selection menu + sink.
- `8 HTML Preview/HTMLPreviewView.swift` (+ `HTMLPreviewCoordinator.swift`, `HTMLPreviewPanel.swift`) — JS policy, selection capture, menu, sink.
- `1 Setup/Module Guides/2 Foundation/2.7 Utilities/guide.md` — new types + consumers.
- `1 Setup/Module Guides/4 Markdown Preview/guide.md` — More Context lookup.
- `1 Setup/Module Guides/8 HTML Preview/guide.md` — More Context lookup + JS policy.
- `1 Setup/Module Guides/9 Resources/9.5 Grammar Help/guide.md` — Mode 3 extended to HTML preview.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed — commit message: `[2 Foundation] More Context shared lookup utility`
- [ ] Pre-push checks done (`git status --short` clean of unrelated changes; `git --no-pager log origin/main..HEAD` reviewed for pre-existing unpushed commits)
- [ ] Pushed to GitHub (`git push origin main`) — all recent changes pushed
- [ ] Plan moved to Plans Completed/
