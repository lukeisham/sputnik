---
plan: Preview sync improvements — latency, scroll sync, partial updates, bidirectional, large files
module: 4 Markdown Preview + 8 HTML Preview + 2 Foundation (2.2 Global State / 2.1 Inter-panel) + 3 Text Editor
created: 2026-06-12
status: draft
related_issues: ISS-061 (Markdown scroll preservation — resolved); ISS-062 (HTML full-reload flicker), ISS-063 (no live scroll sync), ISS-064 (no partial render), ISS-065 (no source map / bidirectional) — logged 2026-06-12
---

## Purpose
Make the live previews feel tightly coupled to the editor: lower the typing→preview latency, keep scroll position aligned in both directions, re-render only what changed, let a click in the preview jump to the source line, and stay responsive on very large Markdown/HTML files.

## Background — current behaviour (verified 2026-06-12)
- **Render trigger & throttle:** Markdown renders via `MarkdownPreviewPanel.onChange(of: activeDocument?.text)` → `viewModel.render()` → `RenderThrottle` (default `delay: 0.1`s, `SputnikShared`) → background `Task` rebuilds the **whole** `NSAttributedString` → published under a generation guard. HTML renders via `HTMLPreviewView.updateNSView` → `coordinator.throttledLoad` → a full `WKWebView.loadHTMLString` of the **entire** document each time.
- **Scroll:** Markdown *position preservation* is now wired (ISS-061 resolved — `MarkdownRenderView` observes the clip view's `boundsDidChangeNotification` and restores per-document offset after each re-render). The **HTML** preview has no equivalent (its full reload resets scroll — ISS-062), and neither preview has live editor↔preview *sync*: the editor publishes **no** visible-line/scroll-fraction to shared state — `scrollOffset` in `LayoutState`/`WindowDescriptor` (2.5) is only persisted for document *restore*, not live sync (ISS-063).
- **Partial updates:** none. Every keystroke (after the debounce) reparses (Markdown) or fully reloads (HTML) the whole document.
- **Bidirectional:** none. Preview link clicks route through `MarkdownPreviewCoordinator` / `HTMLPreviewCoordinator` + `LinkNavigationPolicy`, but there is no mapping from a rendered location back to an editor source line. `AttributedString(markdown:)` does not retain source offsets.
- **Large files:** parse runs off-thread with a generation guard (Markdown); images are downsampled/capped (module 9). But there is no document-size threshold that adjusts sync behaviour, and HTML re-loads the full document regardless of size.

## Success Condition
- **Latency:** Typing in a small/medium document shows in the preview with noticeably less lag than today, with no dropped or flickering frames, and the HTML preview no longer white-flashes or loses scroll on each keystroke.
- **Scroll sync:** Scrolling the editor moves the preview to the corresponding region (proportional or anchor-based), and the preview keeps its position across re-renders (ISS-061 closed). Sync can be toggled off. No feedback loop / oscillation between the two scroll views.
- **Partial updates:** Editing one paragraph/section does not visibly re-render or scroll-jump the rest of the document; large unchanged regions are reused.
- **Bidirectional:** With the option enabled, clicking (or ⌘-clicking) a location in the preview moves the editor caret/selection to the corresponding source line and scrolls it into view; misses degrade gracefully (nearest line, no error).
- **Large files:** Opening a very large Markdown/HTML file keeps the UI responsive; above a size threshold the app switches to a clearly-indicated degraded mode (e.g. manual-refresh or coarser sync) instead of stuttering. No crash, no unbounded memory (SR-3).

## Steps

### Workstream A — Lower typing→preview latency (4 / 8 / 2.7)

- [ ] 1. **Make the render throttle adaptive instead of a fixed 0.1s.**
   What: Replace the single fixed `RenderThrottle(delay: 0.1)` with a small/large-document-aware delay (short for small docs, longer for large), and/or a "leading + trailing" debounce so the first keystroke after a pause renders immediately and subsequent ones coalesce. Tune via `SettingsStore` if a knob is warranted.
   Why: The fixed debounce is the dominant source of perceived lag on small files where rendering is already cheap; an adaptive delay buys responsiveness without re-introducing stutter on large files.

- [ ] 2. **Stop the HTML preview's full-document reload flicker.**
   What: In `HTMLPreviewCoordinator.throttledLoad`, avoid calling `loadHTMLString` for content-only edits: inject the new `<body>` HTML via the existing injected-script channel (update `document.body.innerHTML` / a targeted node) and only do a full reload when the document structure or `<head>`/baseURL changes. Preserve the JS-disabled security posture (the selection-capture `WKUserScript` already runs with page JS off — reuse that mechanism, do not enable page JS).
   Why: A full `loadHTMLString` tears down and rebuilds the whole web page on every keystroke — that is the white-flash and scroll-reset users see; updating the body in place removes it and is the HTML analogue of partial updates (Workstream C).

### Workstream B — Scroll position sync (4 / 8 / 2.2 / 3)

- [ ] 3. **Bring HTML scroll preservation up to Markdown's level.**
   What: Markdown per-document scroll preservation is already wired (ISS-061 resolved). Give the HTML preview the same baseline: preserve/restore the `WKWebView` scroll position across content updates (naturally falls out of the in-place body update in Step 2 — capture `scrollY` before, restore after, via the injected script channel). This is the prerequisite *position-holding* capability both previews need before they can follow the editor.
   Why: A preview must be able to hold and set its own scroll position before it can follow the editor; Markdown already can, HTML cannot (its full reload resets it — ISS-062).

- [ ] 4. **Publish the editor's live scroll position to shared state.**
   What: Have the editor (module 3) report its top visible line (and a fractional offset) to Foundation — e.g. a `previewScrollAnchor` on `WindowState` (2.2) updated from the editor's scroll-view bounds-change observer, throttled. The preview observes it. Keep the editor a writer of *its own* anchor only.
   Why: There is no live editor scroll signal anywhere today; a single shared anchor on `WindowState` is the decoupled channel (SR-1) both previews can read without importing module 3.

- [ ] 5. **Map the editor anchor to a preview position and scroll the previews.**
   What: Translate the editor's source line/fraction into a preview position: for Markdown, via the source map from Step 8 (or a proportional fallback before that lands); for HTML, scroll the `WKWebView` to the matching element/offset via the injected script channel. Add a sync-enable toggle and loop-suppression (ignore programmatic scrolls so editor→preview→editor cannot oscillate).
   Why: This is the actual "keep scroll roughly in sync" feature; explicit loop-suppression is required because both sides observe scroll and would otherwise fight.

### Workstream C — Smart partial updates (4 / 8)

- [ ] 6. **Block-level diffing for the Markdown render.**
   What: Split the Markdown source into top-level blocks (paragraphs/headings/lists/code fences), render per block, and cache each block's rendered `NSAttributedString` keyed by block text hash. On edit, re-render only blocks whose text changed and splice them into the existing `textStorage` instead of replacing the whole string.
   Why: Full reparse on every keystroke is the core inefficiency; block-level caching reuses the (often large) unchanged remainder and removes the whole-document scroll jump. Coarser-than-AST diffing keeps it tractable given `AttributedString(markdown:)` is whole-string.

- [ ] 7. **Confirm HTML partial update path.**
   What: Ensure Step 2's in-place body update is the steady-state path for content edits and that only structural changes trigger a full reload; verify image-scheme rewriting (`sputnik-img://`) and F-4 CSS injection still apply to in-place updates.
   Why: Closes the HTML half of "partial updates"; without re-checking the CSS/image rewrite, an in-place update could drop the per-panel styling that the full-reload path applies.

### Workstream D — Bidirectional awareness (4 / 8 / 3 / 2.1)

- [ ] 8. **Build a source map during Markdown render.**
   What: While splitting/rendering blocks (Step 6), record each rendered block's character range ↔ source line range. Store the map on the view model. (For HTML, attach `data-source-line` attributes to block elements during a lightweight pre-pass, or fall back to proportional mapping.)
   Why: `AttributedString(markdown:)` discards source offsets, so "jump to the line I clicked" is impossible without a map built at parse time; piggybacking on the block split avoids a second pass.

- [ ] 9. **Route a preview click/⌘-click to the editor source line.**
   What: In `MarkdownPreviewCoordinator` (and the HTML coordinator), on a non-link click resolve the clicked character/element to a source line via the Step 8 map and ask the editor to move the caret + scroll there — through a Foundation channel (extend `InterPanelRouter` with `revealSourceLine(_:in:)` or a `WindowState` request), never importing module 3. Gate behind an opt-in toggle so normal text selection still works.
   Why: This is the bidirectional feature; routing through Foundation keeps the preview decoupled from the editor (SR-1), and the opt-in keeps it from stealing ordinary selection clicks.

### Workstream E — Better large-file handling (4 / 8 / 2.3)

- [ ] 10. **Define size thresholds and a degraded mode.**
   What: Introduce document-size thresholds (lines/bytes). Below: full live sync. Above: switch to a degraded mode — longer/adaptive throttle (Workstream A), coarser proportional scroll sync (skip the source map), and/or a "preview paused — refresh" affordance — with a visible indicator of the mode. Surface thresholds in `SettingsStore` (2.3) if tunable. Reuse the editor's existing large-file guard pattern (module 3) rather than inventing a new policy.
   Why: A single render strategy can't serve both a 20-line note and a 50k-line document; explicit thresholds make the degradation predictable and visible instead of silent stutter, satisfying SR-3/SR-4.

### Workstream F — Guides & issues

- [x] 11. **Log gaps + correct the guides (done 2026-06-12).**
   Done: Logged ISS-062 (HTML full-reload flicker), ISS-063 (no live scroll sync), ISS-064 (no partial render), ISS-065 (no source map / bidirectional). Corrected the **4 Markdown Preview** guide (ISS-061 marked wired/resolved, ISS-060 "PARTIAL" note cleared, ISS-064 noted) and the **8 HTML Preview** guide (dropped the inaccurate "scroll-synced" Purpose claim, corrected the render data-flow to `htmlByInjectingOverrides` + `throttledLoad` full reload, fixed the threading note, registered the open issues; `status` → `active`).
   Remaining (do at implementation close-out): when the sync/partial-update steps land, update both guides again to document the partial-update pipeline, source map, and sync channel; note the new `WindowState` anchor in **2.2** / router method in **2.1**; flip ISS-062–065 to resolved.

## Risks and Constraints
- **Touches Foundation (module 2) — flagged per the `!GenerateAPlan` rule.** The shared scroll anchor (2.2) and the new router method (2.1) are read by both previews and written by the editor; verify no module reaches across the boundary directly (SR-1).
- **Two preview modules at once — cross-module change, plan first (this doc).** Sequence: A and B-Step-3 are low-risk and independent; C-Step-6 (block diffing) must land before D-Step-8 (source map) since the map is a by-product of the block split.
- **Scroll feedback loops:** editor and preview both observe scroll; Step 5 *must* suppress programmatic-scroll echoes or the panels will oscillate. Treat this as the primary correctness risk of Workstream B.
- **Markdown source mapping is approximate.** `AttributedString(markdown:)` is whole-string and gives no offsets; the map is block-granular, not character-exact. Bidirectional jump targets the block's source line, not an exact column — set expectations in the UI and guide accordingly.
- **HTML security posture must hold (ISS-010):** page JavaScript stays disabled (`allowsContentJavaScript = false`). In-place body updates and scroll control must go through the existing injected `WKUserScript` / message-handler channel — do not enable page JS, and never fetch remote resources (SR-3).
- **Threading (SW-1/SR-4):** all `NSTextView`/`WKWebView` mutation stays on `@MainActor`; block rendering stays on the background `Task` with the generation guard; the new editor scroll observer must be throttled so it cannot flood `WindowState` on a fast trackpad scroll.
- **Don't regress existing render correctness:** the stale-render generation guard, F-4 per-panel font/background injection, `sputnik-img://` rewriting, link routing, and the `.markdown`/`.ascii` placeholder rules must survive the partial-update rewrite. (Note ISS-060 — `parseIntentKind` returning `nil` — is a pre-existing styling no-op; out of scope here but don't entrench it.)

## Files Affected
- `4 Markdown Preview/MarkdownPreviewViewModel.swift` — adaptive throttle hook; block cache + diff; source map; scrollOffset wiring (Steps 1, 3, 6, 8).
- `4 Markdown Preview/MarkdownPreviewRenderer.swift` — per-block `buildNSAttributedString`/splice; emit source ranges (Steps 6, 8).
- `4 Markdown Preview/MarkdownRenderView.swift` — connect `scrollOffset` to the `NSScrollView`; observe shared anchor; splice into `textStorage` (Steps 3, 5, 6).
- `4 Markdown Preview/MarkdownPreviewCoordinator.swift` — non-link click → source line (Step 9).
- `8 HTML Preview/HTMLPreviewCoordinator.swift` — in-place body update vs full reload; scroll-to-element via injected script; `data-source-line` (Steps 2, 5, 7, 9).
- `8 HTML Preview/HTMLPreviewView.swift` — gate full reload to structural change; preserve CSS/image rewrite on partial update (Steps 2, 7).
- `2 Foundation/2.2 Global State Management/WindowState.swift` — `previewScrollAnchor` (or equivalent) shared channel (Step 4).
- `2 Foundation/2.1 Inter-panel communication/InterPanelRouter.swift`, `AppInterPanelRouter.swift` — `revealSourceLine(_:in:)` (Step 9).
- `3 Text Editor/3.1 Text/EditorView.swift` / `EditorViewModel.swift` — publish live scroll anchor; accept reveal-line requests (Steps 4, 9).
- `SputnikShared/RenderThrottle.swift` (+ `DebounceTimer`) — adaptive/leading-edge debounce option (Step 1).
- `2 Foundation/2.3 Settings/SettingsStore.swift` — sync toggle + size thresholds if tunable (Steps 5, 10).
- Guides: `1 Setup/Module Guides/4 Markdown Preview/guide.md`, `…/8 HTML Preview/guide.md`, `…/2 Foundation/2.1`, `…/2.2`; `1 Setup/References/Issues.md` (Step 11).
