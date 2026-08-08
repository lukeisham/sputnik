---
plan: Give the minimap per-panel targets so it works reliably on the editor, Markdown, and HTML panels at once
module: 2 Foundation (2.4 UI and UX) + consumers 3 Text Editor, 4 Markdown Preview, 8 HTML Preview
created: 2026-07-04
status: pending
related_issues: ISS-213, ISS-214
---

## Purpose
Replace the single per-window minimap target slot with per-column (per-panel) targets so that the minimap renders correct, independent content for the text editor, the Markdown preview, and the HTML preview simultaneously in the side-by-side layout — instead of the panels overwriting one shared slot.

## Success Condition
- With the editor in the `.active` column and the Markdown (or HTML) preview in the `.activePair` column and the minimap enabled, **both** columns show a minimap bound to their own content — scrolling/clicking each minimap moves the correct panel.
- Switching Fit Width in the Markdown panel, or reloading the HTML preview, keeps that panel's minimap bound (no blank or stale minimap).
- Closing/reopening a panel leaves no dangling strong reference to a torn-down `NSScrollView`/`WKWebView` (verified by a scoped `weak var` deinit check or instrument).
- The editor-only minimap behaviour (single panel, no pair) is unchanged.
- `swift build` succeeds for Foundation and all consumer modules; `swift test` passes.

## Steps

- [ ] 1. **Confirm the intended layout contract**
   What: Confirm from the layout code (`DynamicPanelLayout.ColumnRole`: `.active`, `.activePair`, `.viewOnly`) that at most two content columns can host a minimap at once, and decide the target key: keyed by `ColumnRole` (recommended — bounded, matches how panels are placed) rather than by panel identity.
   Why: ISS-214 — the fix's shape depends on how many concurrent minimap targets are real; a `ColumnRole`-keyed model is the smallest change that represents the actual layout without unbounded per-view state.

- [ ] 2. **Model per-column minimap targets in `WindowState`**
   What: In `2 Foundation/2.2 Global State Management/WindowState.swift`, replace the single `minimapTargetScrollView`/`minimapTargetWebView` weak slots with per-column storage — e.g. `minimapScrollTargets: [ColumnRole: WeakBox<NSScrollView>]` and `minimapWebTargets: [ColumnRole: WeakBox<WKWebView>]` (weak-boxed to preserve SW-2 semantics), plus register/clear helpers keyed by role.
   Why: ISS-214 — one slot per window cannot represent two side-by-side panels; keying by column lets each panel own its own target without racing the other.

- [ ] 3. **Add register/clear accessors on `AppState`**
   What: In `2 Foundation/2.2 Global State Management/AppState+ScratchpadAndMinimap.swift`, add `setMinimapScrollTarget(_:for:)` / `setMinimapWebTarget(_:for:)` / `clearMinimapTarget(for:)` pass-throughs to the active window, keyed by `ColumnRole`. Keep `minimapVisible`/`toggleMinimap` unchanged.
   Why: SR-1 — consumers must go through the Foundation state surface, not reach into `WindowState` internals; role-keyed accessors keep the call sites simple.

- [ ] 4. **Make `Minimap()` bind to its own column's target**
   What: In `2 Foundation/2.4 UI and UX/Minimap.swift`, give `Minimap` a `columnRole` parameter (defaulted for the single-panel case) and have it read the target for *that* role from the new per-column storage, choosing `MinimapScrollBinder` vs `MinimapWebBinder` accordingly.
   Why: ISS-214 — the overlay currently reads the one shared slot; it must select the target belonging to the panel that mounted it, or two overlays render the same (last-written) content.

- [ ] 5. **Publish the scroll view reliably from the Markdown bridge**
   What: In `4 Markdown Preview`, set the minimap target from inside `MarkdownRenderView.makeNSView` (where `viewModel.scrollView` is actually assigned) via the new role-keyed accessor, and clear it in `dismantleNSView`; remove the `onAppear` copy of `viewModel.scrollView` that runs before the scroll view exists. Pass the panel's `columnRole` into `Minimap(columnRole:)`.
   Why: ISS-213 — `onAppear` reads `viewModel.scrollView` before `makeNSView` sets it (so the target is nil on first display), Fit Width re-creates the view without re-publishing, and `dismantleNSView` never clears it (dangling strong ref). Publishing/clearing at the bridge lifecycle points fixes all three.

- [ ] 6. **Update the Text Editor panel to the role-keyed API**
   What: In `3 Text Editor/3.1 Text/TextEditorPanel.swift`, replace the `onAppear`/`onDisappear` writes to `minimapTargetScrollView` with the role-keyed register/clear accessors, and pass `columnRole` into `Minimap(columnRole:)`. Prefer publishing from the editor's `NSViewRepresentable` lifecycle if its scroll view is created there (same reliability reasoning as step 5).
   Why: ISS-214 — the editor must register under its own column so that, when paired with a preview, its minimap is not clobbered by the preview's target write.

- [ ] 7. **Update the HTML preview + JSON viewer to the role-keyed API**
   What: In `8 HTML Preview/HTMLPreviewView.swift` / `HTMLPreviewPanel.swift` and `8 HTML Preview/8.1 JSON Viewer/JSONViewerPanel.swift`, register/clear their web/scroll targets by `ColumnRole` and pass `columnRole` into `Minimap(columnRole:)`.
   Why: ISS-214 — same fix for the other two consumers so the whole set (editor, Markdown, HTML, JSON) coexists correctly; the HTML web binder and JSON scroll binder must each bind to their own column.

- [ ] 8. **Clear targets on document/panel teardown to prevent dangling refs**
   What: Ensure every register site has a matching clear (on `dismantleNSView`, `onDisappear`, or document close), and weak-box storage so a missed clear cannot retain a dead view for the app's lifetime.
   Why: ISS-213/SW-2 — the current `dismantleNSView` gap leaves a strong reference to a torn-down scroll view; weak-boxing plus explicit clears closes both the leak and the stale-binding path.

- [ ] 9. **Add/extend tests**
   What: Add tests to `2 Foundation/Tests/FoundationModuleTests.swift` for: (a) registering two different targets under two different `ColumnRole`s keeps both retrievable, (b) clearing one role does not affect the other, (c) a released target read back as `nil` through the weak box (deinit check).
   Why: Locks in the per-column model and the no-dangling-ref guarantee so a refactor can't silently collapse back to one shared slot.

- [ ] 10. **Update the Module Guides**
   What: Update the `2.4 UI and UX` guide (minimap: per-column targets, `Minimap(columnRole:)`, register/clear API) and add the Minimap integration section to the `4 Markdown Preview` guide (also satisfying the minimap portion of ISS-219); note the wiring in the `3 Text Editor` and `8 HTML Preview` guides.
   Why: The current guides describe a single-target minimap (or omit it entirely for module 4); they must reflect the per-column model.

## Risks and Constraints
- **Touches Foundation (module 2.2 + 2.4)** — this is a shared-state and shared-UI change, so every minimap consumer (modules 3, 4, 8, and 8.1) must be rebuilt and re-tested. Flagged explicitly per SR-1 (cross-module change requires a plan — this is it).
- Keep all target references **weak** (weak-boxed in the dictionary) — a strong per-column map would retain scroll/web views and inflate RAM (SR-3, SW-2).
- Do not break the single-panel (editor-only) path: `Minimap(columnRole:)` must have a sensible default so a lone panel still works with no layout pairing.
- `ColumnRole` currently lives in the app layer (`DynamicPanelLayout` in `App-Sputnik`), while `WindowState` lives in Foundation — resolve the dependency direction (either move/alias a minimal role token into Foundation, or key the map on a Foundation-owned enum that the app maps onto). Decide in step 1 and keep Foundation free of app-layer imports (SR-1).
- Execute **after** the two module-4 plans (router/interaction and rendering/lifecycle) land, since this plan revisits `MarkdownPreviewPanel.swift` and `MarkdownRenderView.swift` and builds on the ISS-215 teardown fix.

## Files Affected
- `2 Foundation/2.2 Global State Management/WindowState.swift` — per-column weak-boxed minimap target storage.
- `2 Foundation/2.2 Global State Management/AppState+ScratchpadAndMinimap.swift` — role-keyed register/clear accessors.
- `2 Foundation/2.4 UI and UX/Minimap.swift` — `columnRole` parameter; per-column target selection.
- `4 Markdown Preview/MarkdownRenderView.swift`, `MarkdownPreviewPanel.swift` — publish/clear scroll target at bridge lifecycle; pass `columnRole`.
- `3 Text Editor/3.1 Text/TextEditorPanel.swift` — role-keyed register/clear; pass `columnRole`.
- `8 HTML Preview/HTMLPreviewView.swift`, `HTMLPreviewPanel.swift`, `8 HTML Preview/8.1 JSON Viewer/JSONViewerPanel.swift` — role-keyed register/clear; pass `columnRole`.
- `App-Sputnik/ContentView.swift` — pass each panel's `columnRole` into its `Minimap`, if plumbed from the panel constructor.
- `2 Foundation/Tests/FoundationModuleTests.swift` — per-column target tests.
- Module Guides: `2 Foundation/2.4 UI and UX/guide.md`, `4 Markdown Preview/guide.md`, `3 Text Editor Window/3.1 Text/guide.md`, `8 HTML Preview/guide.md`.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`) — 2.4 UI and UX, 4 Markdown Preview, 3.1 Text, 8 HTML Preview
- [ ] Changes committed: `[2 Foundation] Minimap per-panel targets across editor and previews`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
