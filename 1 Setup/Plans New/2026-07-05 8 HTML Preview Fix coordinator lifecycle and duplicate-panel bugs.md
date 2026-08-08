---
plan: Fix coordinator lifecycle and duplicate-panel bugs
module: 8 HTML Preview
created: 2026-07-05
status: pending
related_issues: ISS-220, ISS-221, ISS-224
---

## Purpose
Give the HTML Preview panel a stable coordinator identity and a single live web view per window, so the Print/Save-as-PDF/Save-as-HTML actions actually fire and the minimap target is never raced between two competing panels.

## Success Condition
- Opening an `.html` file, letting `ContentView`'s body re-evaluate several times (e.g. by toggling any toolbar/sidebar state), then choosing "Print…" or "Save as PDF…" from the overflow menu (or the File-menu paired-preview actions) always operates on the currently-active document — never a silent no-op.
- Only one live `WKWebView` for HTML content exists per window at a time; the Sputnik Help overlay (topic `.sputnik`) reuses the same panel/coordinator instance rather than instantiating a second one.
- Switching the active document, or dismissing/reopening the HTML preview column, updates `WindowState.minimapTargetWebView` exactly once per real change — never nils out a target claimed by a different, still-visible panel.
- `HTMLPreviewModuleTests` still passes; a new test asserts that two `HTMLPreviewView` `updateNSView` passes against the same `makeCoordinator()`-vended coordinator preserve the wired `printAction`.

## Steps

- [ ] 1. **Make `HTMLPreviewCoordinator` ownership stable across body re-evaluations**
   What: Change `HTMLPreviewPanel` to hold its coordinator in `@State private var coordinator: HTMLPreviewCoordinator?` initialized lazily in `.onAppear` (or via a `@State` wrapper seeded from a factory closure captured at `init`), instead of constructing a fresh `HTMLPreviewCoordinator` as a stored `let` in `init`. SwiftUI re-runs `init` on every parent body re-evaluation but preserves `@State` across those re-inits for the same view identity, so the coordinator survives.
   Why: ISS-220 — `HTMLPreviewPanel.init` (HTMLPreviewPanel.swift:69) currently builds a new coordinator on every re-render, but `HTMLPreviewView.makeCoordinator()` is called once by the representable and keeps only the first instance, so later panel structs read `printAction`/`saveAsPDFAction`/`saveAsHTMLAction` off coordinators that were never wired in `makeNSView`.

- [ ] 2. **Remove `makeCoordinator()`'s reliance on being called exactly once for correctness**
   What: Audit `HTMLPreviewView.makeCoordinator()` (HTMLPreviewView.swift:151) and `makeNSView` (HTMLPreviewView.swift:162) — since the representable is handed the same injected coordinator from the now-stable panel state, confirm `makeCoordinator()` remains idempotent (it already returns the injected instance; only re-verify none of its side effects, like setting `onRequestHelp`, assume single-call semantics that would break if SwiftUI ever recreates the coordinator).
   Why: Step 1 changes *what* stays alive; this step confirms the representable's contract doesn't silently regress once coordinator identity is stable, closing out ISS-220 end-to-end.

- [ ] 3. **Eliminate the duplicate router-less panel in the help overlay**
   What: In `App-Sputnik/ContentView.swift` (~line 406), stop instantiating a second, bare `HTMLPreviewPanel()` inside `helpPanelOverlay`. Instead, reuse the same panel instance already rendered in the column layout when the overlay's HTML content is what's being shown, or — if the overlay genuinely needs an independent read-only preview for the bundled Sputnik help document — pass the real `router` and set `helpContextEnabled: false` explicitly rather than relying on the `nil`/default fallback.
   Why: ISS-221 — a second, permanently-mounted, router-less `HTMLPreviewPanel()` renders a duplicate live `WKWebView` for every active HTML document at all times (SR-3 RAM cost) and cannot open links as editor tabs because `router` is `nil`, the same defect class as ISS-211 in Markdown Preview.

- [ ] 4. **Confirm only one HTML preview instance is ever mounted per window**
   What: After step 3, verify (by reading the resulting `ContentView` body and, if needed, adding a debug assertion during manual testing) that at most one `HTMLPreviewPanel`/`HTMLPreviewCoordinator`/`WKWebView` triple is alive per window at any time, across both the normal column layout and the help overlay.
   Why: Removes the root cause of the minimap and paired-preview-action races fixed in step 5 — two live panels can no longer contend for the same single-slot `WindowState` fields.

- [ ] 5. **Stop mutating `WindowState` from `updateNSView`**
   What: In `HTMLPreviewView.updateNSView` (HTMLPreviewView.swift:298), move the `appState.activeWindow?.minimapTargetWebView = webView` write out of the view-sync method. Set it once in `makeNSView` after the web view is created (mirroring how `printAction`/`saveAsPDFAction` are wired once there), and update it again only in response to an actual document-identity change (e.g. from a `.onChange(of: appState.activeDocumentID)` handler on the owning `HTMLPreviewPanel`, matching the pattern `HTMLPreviewPanel.onChange` already uses for `updatePairedPreviewActions()`), not on every `updateNSView` pass.
   Why: ISS-224 — mutating `@Observable` `WindowState` during a SwiftUI view-update pass is the exact anti-pattern ISS-095 already removed from this file; with two panels no longer live (step 3), this also stops the surviving panel from needlessly re-writing a slot nobody else is contending for.

- [ ] 6. **Guard the minimap-clear on disappear**
   What: In `HTMLPreviewPanel.onDisappear` (HTMLPreviewPanel.swift:98), only clear `appState.activeWindow?.minimapTargetWebView` when it currently equals this panel's own web view (compare via the coordinator's stored `weak var webView`), matching the identity-check pattern `JSONViewerPanel.onDisappear` already uses for `minimapTargetScrollView`.
   Why: Prevents a stale teardown from nil-ing out a target some other still-visible panel just claimed — defensive even after step 4 removes the known duplicate-panel source, since future overlay/paired-preview panels could reintroduce a second instance.

- [ ] 7. **Add a coordinator-identity regression test**
   What: In `Tests/HTMLPreviewModuleTests.swift`, add a test that constructs an `HTMLPreviewCoordinator`, wires a `printAction` closure (as `makeNSView` would), simulates a second `HTMLPreviewView(coordinator:)` init with the *same* coordinator instance, and asserts `printAction` is still set and callable — codifying the fix so a future refactor can't reintroduce ISS-220.
   Why: Success Condition requires a regression test; this is the cheapest reliable check without a full UI test harness for WKWebView.

- [ ] 8. **Manual verification pass**
   What: Run the app (via the `run` skill), open an `.html` file, trigger several unrelated SwiftUI state changes (toggle sidebar, switch tabs, resize window), then use "Save as PDF…" and confirm a real PDF is written. Separately, open the Sputnik Help overlay and confirm only one HTML preview renders and its links (if any) open as editor tabs.
   Why: Type-checking and unit tests don't verify WKWebView runtime behavior or SwiftUI view-identity lifetimes; this closes the loop per the project's UI-verification convention.

## Risks and Constraints
- SwiftUI's `@State` survives across `init` re-invocations only when the view's *identity* (position in the view tree) is stable; if `ContentView.panelView`'s `switch` causes `HTMLPreviewPanel` to be rebuilt at a different tree position (e.g. via `AnyView` erasure or conditional branches), `@State` will still reset. Verify the surrounding `switch renderMode` branch structure keeps a stable identity before relying on this fix (SW-3, SR-2).
- Removing the second `HTMLPreviewPanel()` from the help overlay changes what the Sputnik Help topic actually displays — confirm with a quick manual check that the bundled help document still renders correctly after the change (don't silently drop the feature).
- This plan touches the app-shell file `App-Sputnik/ContentView.swift`, which is shared scaffolding, not a module boundary — keep the diff minimal and scoped to the HTML preview instantiation sites only.

## Files Affected
- `8 HTML Preview/HTMLPreviewPanel.swift` — stable `@State` coordinator ownership; guarded minimap-clear on disappear.
- `8 HTML Preview/HTMLPreviewView.swift` — move `minimapTargetWebView` write out of `updateNSView` into `makeNSView` + a targeted `onChange`.
- `App-Sputnik/ContentView.swift` — remove/rework the duplicate router-less `HTMLPreviewPanel()` in `helpPanelOverlay`.
- `8 HTML Preview/Tests/HTMLPreviewModuleTests.swift` — new coordinator-identity regression test.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[8 HTML Preview] Fix coordinator lifecycle and duplicate-panel bugs`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
