---
plan: Unify Help Navigation Route
module: 2 Foundation / 9 Resources
created: 2026-06-09
status: complete
related_issues: ISS-002, ISS-004, ISS-008
---

## Purpose
Replace the three ad-hoc help-panel navigation mechanisms (a `NotificationCenter` post in `GrammarHelpCoordinator` and `openTopicHandler` closures in `MarkdownHelpCoordinator` and `HTMLHelpCoordinator`) with the single Foundation-owned `AppState.requestedHelpTarget` route — closing ISS-008 and recording the already-resolved ISS-002 and ISS-004 as done.

## Success Condition
- `GrammarHelpCoordinator.openHelp(for:)` writes to `AppState.requestedHelpTarget`; no `NotificationCenter` post or observation exists for help-panel navigation.
- `MarkdownHelpCoordinator` and `HTMLHelpCoordinator` have no `openTopicHandler` property; both write to `AppState.requestedHelpTarget`.
- The `Notification.Name.grammarHelpOpenTopic` extension is deleted; no project file references it.
- All three help panels open and navigate to the correct topic when triggered from the editor right-click menu.
- ISS-002, ISS-004, and ISS-008 are marked Resolved in `References/Issues.md`.

## Context
The Foundation route is already partially in place:
- `HelpRequest` (kind + optional `topicID`) lives in `2 Foundation/2.4 UI and UX/HelpTopic.swift`.
- `AppState.requestedHelpTarget: HelpRequest?` is live in `AppState.swift`.
- `SputnikHelpPanel` already observes `requestedHelpTarget` and calls `navigate(to:)`.
- `EditorView` already writes `appState.requestedHelpTarget = request` from the editor right-click path.

The remaining gap: the three help coordinators still use old, ad-hoc routes that bypass the Foundation seam.

## Steps

- [ ] 1. **Mark ISS-002 and ISS-004 resolved in Issues.md**
   What: Update `References/Issues.md` rows for ISS-002 and ISS-004 — set each Status column to "Resolved — 2026-06-09: SettingsStore fields and consumer wiring confirmed complete; no local defaults remain."
   Why: Both fixes are already in the code (`TerminalView` reads from `SettingsStore`; all six editor files inject and use `SettingsStore`). The log is stale and should be accurate.

- [ ] 2. **Inject AppState into GrammarHelpCoordinator**
   What: Add a `var onNavigate: ((HelpRequest) -> Void)?` closure property to `GrammarHelpCoordinator`. Wire it at the point where the coordinator is set up (e.g. `GrammarHelpPanelView.task` or the app root) by assigning `coordinator.onNavigate = { [weak appState] request in appState?.requestedHelpTarget = request }`.
   Why: `GrammarHelpCoordinator.shared` is a singleton; a closure (captured weakly) avoids a retain cycle (SW-2). The coordinator must not hold `AppState` as a strong stored property.

- [ ] 3. **Replace GrammarHelpCoordinator.openHelp(for:) with AppState write**
   What: In `GrammarHelpCoordinator.openHelp(for:)` (`9 Resources/9.5 Grammar Help/GrammarHelpCoordinator.swift` line 98–105), replace the `NotificationCenter.default.post(name: .grammarHelpOpenTopic, ...)` call with `onNavigate?(HelpRequest(kind: .grammar, topicID: topic.id))`. Update `openLastResult()` to use the same path.
   Why: `SputnikHelpPanel` observes `requestedHelpTarget`; the notification is an orphaned route that currently does nothing (no observer exists in `GrammarHelpPanelView` or anywhere else).

- [ ] 4. **Delete the grammarHelpOpenTopic Notification.Name extension**
   What: Remove the `extension Notification.Name { static let grammarHelpOpenTopic = ... }` block at the bottom of `GrammarHelpCoordinator.swift` (lines 122–129). Search the whole project for `grammarHelpOpenTopic` to confirm no remaining references.
   Why: Dead code with no observers. Removing it prevents future confusion about which navigation route is canonical (SR-6).

- [ ] 5. **Replace MarkdownHelpCoordinator.openTopicHandler with AppState write**
   What: In `9 Resources/9.3 Markdown Help/MarkdownHelpCoordinator.swift`:
   - Remove `public var openTopicHandler: ((String) -> Void)?` (line 24).
   - Add `var onNavigate: ((HelpRequest) -> Void)?` in its place.
   - Replace `openTopicHandler?(topicID)` (line 154) with `onNavigate?(HelpRequest(kind: .markdown, topicID: topicID))`.
   - Wire `onNavigate` at the call site with the same weak-capture closure pattern as step 2.
   Why: Removes the ad-hoc closure seam; Markdown Help now uses the same navigation path as Grammar Help.

- [ ] 6. **Replace HTMLHelpCoordinator.openTopicHandler with AppState write**
   What: Same as step 5 for `9 Resources/9.4 Html Help/HTMLHelpCoordinator.swift`:
   - Remove `public var openTopicHandler: ((String) -> Void)?` (line 18).
   - Add `var onNavigate: ((HelpRequest) -> Void)?`.
   - Replace `openTopicHandler?(topicID)` (line 96) with `onNavigate?(HelpRequest(kind: .html, topicID: topicID))`.
   - Wire `onNavigate` at the call site.
   Why: Removes the last ad-hoc navigation route. All three help coordinators now funnel through `AppState.requestedHelpTarget` — ISS-008 is closed.

- [ ] 7. **Verify SputnikHelpPanel.navigate(to:) handles all three HelpTopic kinds**
   What: Read `9 Resources/SputnikHelpPanel.swift` lines around `navigate(to:)` (line 179). Confirm the switch/if handles `.grammar`, `.markdown`, and `.html`. Fix any missing branch.
   Why: `SputnikHelpPanel` is the shared receiver; a missing kind would silently swallow navigation requests from steps 3, 5, and 6.

- [ ] 8. **Mark ISS-008 resolved in Issues.md**
   What: Update `References/Issues.md` ISS-008 row — set Status to "Resolved — 2026-06-09: `HelpRequest` + `AppState.requestedHelpTarget` is the single Foundation route; `GrammarHelpCoordinator` NotificationCenter path and `openTopicHandler` closures in Markdown/HTML coordinators removed; all three coordinators use `onNavigate` wired to `AppState`."
   Why: Closes the issue with a precise, reproducible description of the fix for future reference.

- [ ] 9. **Update module guides**
   What: In `1 Setup/Module Guides/2 Foundation/2.4 UI and UX/guide.md`, confirm the `HelpRequest` entry documents `onNavigate` as the coordinator-side wiring pattern. In `1 Setup/Module Guides/9 Resources/9.5 Grammar Help/guide.md`, update `last_updated` and revise the coordinator section to reflect the `onNavigate` → `AppState` path.
   Why: Module guides are the source of truth; they must reflect the final implementation (per working conventions).

## Risks and Constraints
- **SW-2 (Retain cycles):** The `onNavigate` closure must capture `AppState` weakly (`[weak appState]`). Coordinators are singletons that outlive any individual view; a strong capture would prevent `AppState` from deallocating.
- **SR-1 (Modular design):** Module 9 coordinators writing a single property on `AppState` is the prescribed cross-module route — Foundation owns `AppState` and exposes it for writes. This is not a violation; it is the pattern.
- **Dead observer check (step 4):** Run a project-wide search for `grammarHelpOpenTopic` before deleting. If any call site was wired to an observer elsewhere, it must be removed at the same time.
- **ISS-002 / ISS-004:** No code changes — documentation-only updates to `Issues.md`.

## Files Affected
- `1 Setup/References/Issues.md` — mark ISS-002, ISS-004, ISS-008 resolved
- `9 Resources/9.5 Grammar Help/GrammarHelpCoordinator.swift` — replace NotificationCenter path with `onNavigate`; add `onNavigate` property; delete notification name extension
- `9 Resources/9.3 Markdown Help/MarkdownHelpCoordinator.swift` — replace `openTopicHandler` with `onNavigate`
- `9 Resources/9.4 Html Help/HTMLHelpCoordinator.swift` — replace `openTopicHandler` with `onNavigate`
- `9 Resources/SputnikHelpPanel.swift` — verify `navigate(to:)` branch coverage (read-only unless a gap is found)
- Coordinator call sites (wherever `GrammarHelpCoordinator.shared`, `MarkdownHelpCoordinator`, `HTMLHelpCoordinator` are wired up) — add `onNavigate` closure assignment
- `1 Setup/Module Guides/2 Foundation/2.4 UI and UX/guide.md` — update `last_updated`
- `1 Setup/Module Guides/9 Resources/9.5 Grammar Help/guide.md` — update `last_updated`, revise coordinator description

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
- [x] Success Condition verified (confirmed as described above)
- [x] Module Guide(s) updated (`status` + `last_updated`)
- [x] Changes committed: `[Foundation / Resources] Unify help navigation route (ISS-008)`
- [x] Plan moved to Plans Completed/
