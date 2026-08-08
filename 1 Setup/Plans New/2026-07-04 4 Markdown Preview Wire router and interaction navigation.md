---
plan: Wire the router and interaction/settings into the Markdown Preview
module: 4 Markdown Preview
created: 2026-07-04
status: pending
related_issues: ISS-211, ISS-212
---

## Purpose
Make the Markdown preview's cross-panel navigation and the "Interaction" context-menu path actually function by injecting the dependencies (`InterPanelRouter`, `SettingsStore`, `InteractionCoordinator`) that the panel and coordinator already expect but are never given in production.

## Success Condition
- Clicking a `file://` link in the rendered Markdown opens (or focuses) that file as an editor tab via `InterPanelRouter.open(_:)` instead of doing nothing.
- With `bidirectionalEnabled` on, ⌘-clicking rendered text reveals the corresponding source line in the editor (`revealSourceLine`) instead of doing nothing.
- With the WritingAssist "Interaction" toggle enabled for Markdown, right-clicking a selected special element in the preview shows the interaction menu item; with it disabled, the item is absent.
- `swift build` succeeds; existing module 4 tests still pass.

## Steps

- [ ] 1. **Inject the router at the panel construction site**
   What: In `App-Sputnik/ContentView.swift` where `MarkdownPreviewPanel(helpContextEnabled:)` is built (the `.markdownPreview` case), pass `router: router` exactly as the adjacent `.htmlPreview` case already does.
   Why: ISS-211 — the panel's `router:` parameter defaults to `nil`, so `MarkdownPreviewCoordinator.router` is nil and all `file://` link clicks and ⌘-click navigations are silent no-ops. This is the single missing argument that makes link/⌘-click navigation dead in production.

- [ ] 2. **Confirm the router reference survives panel re-creation**
   What: Verify the `router` passed in ContentView is the same long-lived `InterPanelRouter` instance used by the other panels (held by the app root), and that `MarkdownPreviewCoordinator` continues to hold it `weak` (no ownership change). Add no new storage — just confirm and document at the call site.
   Why: SW-2 — the coordinator holds `router` weakly to avoid a retain cycle; injecting a short-lived or per-render router would let it deallocate and silently re-break navigation. The fix must not introduce a strong cycle.

- [ ] 3. **Wire `settingsStore` and `interactionCoordinator` onto the coordinator**
   What: In `MarkdownPreviewPanel.body`'s `.task` block (where `helpContextResolver`, `onRequestHelp`, and `viewModel` are already assigned), also assign `coordinator.settingsStore` and `coordinator.interactionCoordinator` from the app's shared instances. Source `SettingsStore` from the existing `@Environment(SettingsStore.self)`; obtain the shared `InteractionCoordinator` the same way the Text Editor / HTML panels obtain theirs (mirror their wiring — do not construct a fresh one per panel).
   Why: ISS-212 — these two properties are never assigned, so `interactionEnabled` in the right-click handler is always `false` and the interaction auto-fill path is unreachable. They must be wired for the gate to reflect the real WritingAssist setting.

- [ ] 4. **Gate interaction wiring on `helpContextEnabled`**
   What: Only assign `interactionCoordinator` (and enable the interaction path) when the panel instance is interactive (`helpContextEnabled == true`, i.e. `.active`/`.activePair` columns), leaving it `nil` for view-only columns.
   Why: SR-1 / consistency — view-only preview columns must not offer editing-style interactions; matching the existing `helpContextEnabled` gate keeps behaviour uniform with the HTML panel.

- [ ] 5. **Verify no duplicate/leaked coordinator wiring on re-render**
   What: Confirm the `.task` wiring runs against the single coordinator created in `init` (not a fresh one), and that reassigning `settingsStore`/`interactionCoordinator` on an already-wired coordinator is idempotent.
   Why: The coordinator is created once and held for the panel's lifetime (existing invariant); the new assignments must respect that and not create per-render churn (SR-4).

- [ ] 6. **Update the Module Guide's dependency + coordinator sections**
   What: In `1 Setup/Module Guides/4 Markdown Preview/guide.md`, document that the panel injects `router`, `settingsStore`, and `interactionCoordinator` into the coordinator, and list the coordinator's `settingsStore`/`interactionCoordinator`/`linksEnabled` properties (partial ISS-219 closeout for the wiring surface touched here).
   Why: The guide currently implies the coordinator is fully wired by `.task`; it omits these dependencies, so it misrepresents the live data flow.

## Risks and Constraints
- **Touches the app root (`ContentView.swift`)**, not just module 4 — but it is a one-argument addition mirroring an existing sibling call; no Foundation API changes. Flagged per the "cross-module change" rule.
- Must not introduce a retain cycle: `router` stays `weak` on the coordinator; `interactionCoordinator` should follow whatever ownership the editor/HTML panels already use for it — replicate, don't invent.
- Do not change `MarkdownPreviewCoordinator`'s public API; only assign already-declared properties.
- This plan shares `MarkdownPreviewPanel.swift` with the minimap plan (ISS-213/214) — execute and commit this plan first, then rebase the minimap work on top to avoid a merge conflict in the `.task`/`.onAppear` region.

## Files Affected
- `App-Sputnik/ContentView.swift` — pass `router: router` into the `.markdownPreview` panel case.
- `4 Markdown Preview/MarkdownPreviewPanel.swift` — assign `coordinator.settingsStore` and `coordinator.interactionCoordinator` in `.task`, gated on `helpContextEnabled`.
- `1 Setup/Module Guides/4 Markdown Preview/guide.md` — document injected dependencies.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`) — `1 Setup/Module Guides/4 Markdown Preview/guide.md`
- [ ] Changes committed: `[4 Markdown Preview] Wire router and interaction navigation`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
