---
plan: Fix image handler, wiring, and JSON viewer bugs
module: 8 HTML Preview
created: 2026-07-05
status: pending
related_issues: ISS-222, ISS-223, ISS-225, ISS-226, ISS-227, ISS-228, ISS-229
---

## Purpose
Close out the remaining correctness and hygiene defects in the HTML/JSON preview panel — a crash-capable image handler, dead interaction wiring, unsafe delegate signatures, a cosmetic reload button, a JSON-viewer minimap lifecycle bug, and a stacked-header layout defect — then bring the Module Guide back in line with the code.

## Success Condition
- Right-clicking selected text in the HTML preview with Interaction enabled in Settings actually offers the auto-fill "Interaction" item (not silently absent).
- Rapidly switching away from an `.html` document while local images are still loading never crashes the app; served image bytes are the resolver's actual (compressed) format/size, not a re-encoded uncompressed TIFF.
- `didFail`/`didFailProvisionalNavigation` compile against `WKNavigation!` and do not force-unwrap a nil navigation.
- "Reload Preview" in the overflow menu visibly forces a full re-render (e.g. after editing CSS-affecting settings, the change appears immediately without switching tabs).
- Closing and reopening the JSON viewer panel repeatedly does not leak `NSScrollView` instances, and the minimap reliably binds to the currently-visible JSON scroll view.
- When a `.json` file is active, only `JSONViewerPanel`'s own header/toolbar is visible — no HTML-only header or inert toolbar buttons above it.
- `1 Setup/Module Guides/8 HTML Preview/guide.md` accurately describes the Minimap integration, `SelectionContextMenu`/Interaction gating, the `8.1 JSON Viewer` file location, the overflow menu, and matches the JSON view-model's actual debouncing mechanism; `status` and `last_updated` are refreshed.

## Steps

- [ ] 1. **Wire `settingsStore` and `interactionCoordinator` onto the coordinator**
   What: Find where the equivalent Markdown Preview fields are (or will be, per ISS-212) assigned onto `MarkdownPreviewCoordinator`, and apply the same pattern to `HTMLPreviewCoordinator.settingsStore` / `.interactionCoordinator` (HTMLPreviewCoordinator.swift:49-52) — set both from `HTMLPreviewPanel`/`HTMLPreviewView` at the same point `helpContextResolver` is already wired (`makeCoordinator()`, HTMLPreviewView.swift:151-160), sourcing `settingsStore` from the `@Environment(SettingsStore.self)` already available and `interactionCoordinator` from wherever the app constructs its single shared instance.
   Why: ISS-222 — with both properties permanently `nil`, `MoreContextWebView.willOpenMenu`'s Interaction gate (HTMLPreviewView.swift:30-58) always evaluates `false`, making the auto-fill path dead code regardless of the user's setting.

- [ ] 2. **Make `SputnikImageSchemeHandler.stop(_:)` actually cancel in-flight work**
   What: Track the running `Task` per `WKURLSchemeTask` (e.g. a `[ObjectIdentifier: Task<Void, Never>]` dictionary keyed by the task, or wrap each request in a cancellable handle) in `SputnikImageSchemeHandler` (SputnikImageSchemeHandler.swift:22-71); in `webView(_:stop:)` (line 73), cancel and remove the matching task instead of no-op'ing; before calling `didReceive`/`didFinish` inside the detached `Task`, check `Task.isCancelled` (or that the task is still registered) and bail out silently if the request was stopped.
   Why: ISS-223 (part 1) — responding on a stopped `WKURLSchemeTask` raises an NSException and crashes the app (e.g. navigating away from a document while its images are still loading), violating SR-2.

- [ ] 3. **Serve the resolver's actual bytes instead of re-encoding as TIFF**
   What: Change the `Task(priority: .utility)` block in `SputnikImageSchemeHandler.webView(_:start:)` (lines 51-70) to read the `Data` and real MIME type directly off the `PreviewImageResolver.resolve(...)` result's `.image(let data, let mimeType, _)` case (adjust the resolver's return signature if it doesn't already expose a MIME type) and pass those straight to `respond(_:data:mimeType:)`, removing the `NSImage(data:)` → `tiffRepresentation` round-trip entirely.
   Why: ISS-223 (part 2) — decoding already-downsampled compressed bytes to `NSImage` and re-serving as uncompressed TIFF multiplies memory and payload size, defeating the point of downsampling (SR-3).

- [ ] 4. **Reuse a shared `PreviewImageResolver` instead of constructing one per request**
   What: Replace the per-call `let resolver = PreviewImageResolver()` (SputnikImageSchemeHandler.swift:54) with a shared instance — either a singleton already used elsewhere for this purpose, or one injected into `SputnikImageSchemeHandler` at construction time (`HTMLPreviewView.makeNSView`, where `imageHandler.coordinator` is already assigned).
   Why: ISS-223 (part 3) — the doc comment claims a shared cache but a fresh resolver defeats any in-memory caching `PreviewImageCache` (module 2.9) offers; this is a small local fix distinct from the `PreviewImageCache.maxDimension`/`generation` fix already tracked separately under ISS-154 in the Foundation Persistence plan.

- [ ] 5. **Fix the `WKNavigation` optionality mismatch**
   What: Change `didFail(navigation:withError:)` and `didFailProvisionalNavigation(navigation:withError:)` (HTMLPreviewCoordinator.swift:266-287) to declare `navigation: WKNavigation!`, matching `didFinish`'s existing signature and the actual `WKNavigationDelegate` protocol, and guard any use of `navigation` inside the bodies against `nil` (currently neither body reads `navigation`, so this is a signature-only fix).
   Why: ISS-225 — the WebKit API vends `WKNavigation!` and does pass `nil` for some provisional failures; a non-optional Swift parameter receiving nil from Objective-C is undefined behavior (SR-2).

- [ ] 6. **Make "Reload Preview" actually reload**
   What: In `HTMLPreviewPanel`'s overflow menu (HTMLPreviewPanel.swift:165-167), change the "Reload Preview" action to, in addition to clearing `loadError`, invalidate the coordinator's render cache (`lastStyledInputHash = 0` or similar sentinel) and force a fresh `throttledLoad`/`loadHTMLString` pass — the simplest correct approach is exposing a `coordinator.forceReload()` method that resets `lastStyledInputHash`, `lastFullLoadHead`, and `isBaseLoaded`, then calls `webView?.reload()` if a base is already loaded, or lets the next `updateNSView` pass do a full reload.
   Why: ISS-226 — today the button only clears the error banner state; nothing about the actual rendered content changes, making it a cosmetic no-op (SR-2, silent-no-op).

- [ ] 7. **Fix JSON viewer minimap wiring timing and add teardown**
   What: In `JSONViewerPanel` (8.1 JSON Viewer/JSONViewerPanel.swift), move the `appState.activeWindow?.minimapTargetScrollView = viewModel.scrollView` assignment (line 105) to fire only after `JSONTextViewRepresentable.makeNSView` has actually set `viewModel.scrollView` — e.g. via a `.onChange(of: viewModel.scrollView)`-driven update instead of (or in addition to) `.onAppear`, mirroring whatever fix pattern the Markdown Preview equivalent (ISS-213) adopts. Add a `dismantleNSView` to `JSONTextViewRepresentable` that nils `viewModel.scrollView` when the view is torn down.
   Why: ISS-227 — `onAppear` firing before `makeNSView` leaves the minimap unbound on first load, and no `dismantleNSView` means `viewModel.scrollView` keeps a strong reference to a deallocated `NSScrollView` after the panel closes (SW-2).

- [ ] 8. **Suppress the HTML header/toolbar when a JSON file is active**
   What: In `HTMLPreviewPanel.body` (HTMLPreviewPanel.swift:76-83), gate `headerBar` and `toolbar` behind `appState.activeDocument?.fileType != .json` (or restructure `contentArea`'s existing `if session.fileType == .json { JSONViewerPanel() }` branch so it returns the JSON panel as the *entire* body for that case, bypassing the outer `VStack` header/toolbar/divider chrome altogether).
   Why: ISS-228 — today `HTMLPreviewPanel` always renders its own "HTML PREVIEW" header and inert HTML toolbar (Fit Width, Link Navigation, Scroll Sync) above `JSONViewerPanel`'s own header, producing a double header with dead controls; the guide already documents "JSON viewer has no toolbar" as the intended behavior.

- [ ] 9. **Verify build and existing tests**
   What: Build the `HTMLPreviewModule` package and run `HTMLPreviewModuleTests` + `JSONViewerTests` after steps 1-8; add or update tests for the reload-forces-refresh behavior (step 6) and the scroll-view teardown (step 7) where feasible without a full AppKit test harness.
   Why: Confirms no regression in the existing `LinkNavigationPolicy`/coordinator/JSON-render test coverage before touching the guide.

- [ ] 10. **Manual verification pass**
   What: Run the app (via the `run` skill): (a) enable Interaction for HTML in Settings, select text in the HTML preview, right-click, confirm the auto-fill item appears; (b) open an HTML file with several local `<img>` tags, switch tabs rapidly while they load, confirm no crash; (c) click "Reload Preview" after changing the per-panel HTML font/background and confirm the preview updates without switching tabs; (d) open and close a `.json` file a few times and confirm the minimap binds correctly and no double-header renders.
   Why: WKWebView crash timing, minimap binding, and visual layout can't be verified by the type checker or unit tests alone.

- [ ] 11. **Bring the Module Guide back in line with the code**
   What: Update `1 Setup/Module Guides/8 HTML Preview/guide.md` to document: the `Minimap()` overlay and `minimapTargetWebView`/`minimapTargetScrollView` wiring (post-fix, from the previous plan and step 7 here); the `SelectionContextMenu.items(...)`/`SpecialElementDetector` Interaction-gated context menu (replacing the stale `MoreContextMenu.items` description); the `8.1 JSON Viewer/` file location and `Tests/JSONViewerTests.swift`; the overflow menu (Save as HTML…, Save as PDF…, Print…, Reveal in Finder, Reload Preview); and correct the `JSONViewerViewModel` doc comment's debouncing claim (plain `Task` cancellation, not `RenderThrottle`). Set `last_verified` and `last_updated` to today's date.
   Why: ISS-229 — the guide (last verified 2026-06-15) predates all of the above; per CLAUDE.md, the guide is the source of truth for this module's design intent and must not lag a completed fix cycle.

## Risks and Constraints
- Steps 2-4 touch `WKURLSchemeTask` lifecycle directly — test carefully against real navigation-cancellation scenarios (tab switch mid-load), since an incorrect cancellation guard can itself introduce a crash or a permanently-blank image (SR-2).
- Step 4's shared-resolver change must not reintroduce the `PreviewImageCache.generation`/`maxDimension` issue tracked as ISS-154 in the Foundation Persistence plan — if that plan lands first, prefer whatever shared-cache API it produces; if this plan lands first, keep the resolver change minimal (construction-site only) so it doesn't conflict.
- Step 8's restructuring must preserve `Minimap()`, `.onChange`, `.onAppear`, `.onDisappear` behavior for the JSON case — verify the JSON viewer's own minimap/lifecycle wiring (step 7) is unaffected by wherever the header/toolbar gate is inserted.
- This plan assumes the coordinator-lifecycle plan (`2026-07-05 8 HTML Preview Fix coordinator lifecycle and duplicate-panel bugs.md`) lands first or is running in parallel on a separate concern — steps here do not depend on it, but both plans touch `HTMLPreviewPanel.swift` and `HTMLPreviewView.swift`, so land them sequentially to avoid merge conflicts.

## Files Affected
- `8 HTML Preview/HTMLPreviewCoordinator.swift` — `settingsStore`/`interactionCoordinator` wiring; `WKNavigation!` signature fix; `forceReload()` helper.
- `8 HTML Preview/HTMLPreviewView.swift` — pass `settingsStore`/`interactionCoordinator` at coordinator-setup time.
- `8 HTML Preview/HTMLPreviewPanel.swift` — "Reload Preview" action; header/toolbar suppression for `.json`.
- `8 HTML Preview/SputnikImageSchemeHandler.swift` — task cancellation tracking; direct byte/MIME-type serving; shared resolver.
- `8 HTML Preview/8.1 JSON Viewer/JSONViewerPanel.swift` — minimap wiring timing fix.
- `8 HTML Preview/8.1 JSON Viewer/JSONViewerViewModel.swift` — doc-comment correction (debouncing description) if touched by step 11's guide alignment reveals a code-side fix is also warranted.
- `8 HTML Preview/Tests/HTMLPreviewModuleTests.swift`, `8 HTML Preview/Tests/JSONViewerTests.swift` — new/updated tests for steps 6-7.
- `1 Setup/Module Guides/8 HTML Preview/guide.md` — full drift correction (ISS-229).

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[8 HTML Preview] Fix image handler, wiring, and JSON viewer bugs`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
