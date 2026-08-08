---
plan: Router compliance, render-path cleanup, and guide drift
module: 5 PDF Viewer
created: 2026-07-02
status: pending
related_issues: ISS-174, ISS-175, ISS-176, ISS-177, ISS-178, ISS-179
---

## Purpose
Bring the PDF Viewer's file-open path back through the InterPanelRouter contract, remove main-thread disk I/O from the render path, tighten state encapsulation, and clean up stray build artifacts and stale guide content.

## Success Condition
- Opening a PDF via the panel's own "Open…" button/`NSOpenPanel` produces the same `.fileOpened` panel event on `InterPanelRouter.events` that opening via the File Tree does (verifiable by a test or by observing the event stream).
- Zooming out immediately after a document opens in fit-to-width mode zooms from the currently-visible fit scale, not a stale stored value.
- The status bar's file-size string is computed once per document load, not on every page-change/zoom re-render (verify via a log/breakpoint or a test asserting `attributesOfItem` call count).
- `PDFViewerViewModel.document` cannot be set from outside the view model except through `loadPDF`/`loadImage`/`closeDocument`.
- `5 PDF Viewer/` contains no orphaned build-artifact files from other modules; `Package.swift`'s exclude list no longer enumerates them.
- `1 Setup/Module Guides/5 PDF Viewer/guide.md` has `Source Files` and `Invariants` sections per the CLAUDE.md Module Guide Format, and its threading/zoom-control descriptions match the actual code.

## Steps

- [ ] 1. **Route "Open…" through InterPanelRouter**
   What: Give `PDFViewerPanel` access to the app's `InterPanelRouter` (via `@Environment` or an injected dependency, matching how `FileTreePanel` receives it through `init(router:)` — check how `PDFViewerPanel` is instantiated in the layout composition root to pick the consistent pattern) and change `openPanel()` to call `await router.open(url)` instead of `appState.openDocument(url:)` directly.
   Why: ISS-174 — the direct call bypasses the `.fileOpened` panel event that other panels rely on, the same SR-1 cross-module contract violation already fixed for the File Tree under ISS-029.

- [ ] 2. **Sync `scaleFactor` when leaving fit-to-width via zoom**
   What: In `PDFViewerViewModel.zoomIn()`/`zoomOut()`, when transitioning out of fit-to-width mode (`isFitToWidth` was `true`), first read the `PDFView`'s actual current `scaleFactor` (via a new lightweight query action similar to `navigateAction`/`printAction`, e.g. `currentScaleQuery: (() -> CGFloat)?` wired by `PDFKitView.makeNSView`) and seed `scaleFactor` from that value before applying the zoom delta, instead of starting from whatever stale value was last stored.
   Why: ISS-175 — zooming out immediately after opening in fit-to-width mode currently starts from a stale default (1.0) instead of the visually-fit scale, causing a visible jump.

- [ ] 3. **Cache the file size string per document load**
   What: Compute the formatted file-size string once in `PDFViewerViewModel.loadPDF`/`loadImage` (or right after, in `PDFViewerPanel.handleActiveDocumentChange`) and store it as a `@Observable` property (e.g. `PDFViewerViewModel.fileSizeString: String?`), reset on `closeDocument`; update `PDFViewerPanel.statusBar` to read that cached value instead of calling `fileSizeString(for:)` (which hits `FileManager.attributesOfItem`) inside the view body.
   Why: ISS-176 — the current implementation performs synchronous disk I/O inside the SwiftUI view body on every page-change and zoom re-render, violating SR-4 (main thread renders UI only).

- [ ] 4. **Encapsulate `document` as `private(set)`**
   What: Change `PDFViewerViewModel.document` from `public var` to `public private(set) var`, matching the pattern already used for `rootNode`/`activeDirectory` in `FileTreeViewModel`. Audit all call sites (`PDFKitView`, `PDFViewerPanel`, sidebars, tests) to confirm nothing outside the view model assigns to it directly; if `Tests/PDFViewerModuleTests.swift` currently sets `document` directly for test setup, add a small `@testable`-only helper or route tests through `loadPDF`/`loadImage` instead.
   Why: ISS-177 — a publicly settable `document` lets external code bypass the page-count/size-limit checks and thumbnail-cache reset that `loadPDF`/`loadImage` enforce.

- [ ] 5. **Delete stray build artifacts and simplify `Package.swift`**
   What: Delete the 24 orphaned `ASCIIArtHelp*`/`MarkdownHelp*` `.d`/`.dia`/`.swiftdeps`/`.swiftmodule` files from `5 PDF Viewer/` (confirm via `git status`/`git log` that they are indeed leftover build products and not intentionally-committed source, then remove them and drop the corresponding entries from `Package.swift`'s `exclude` array — keep only the genuine excludes: `.build`, `.swiftpm`, `Package.swift`, `Tests`).
   Why: ISS-178 — these files belong to other modules' targets, were committed by mistake, and their one-by-one enumeration in `Package.swift` is dead weight that will keep needing updates as more stale artifacts accumulate.

- [ ] 6. **Add a `.gitignore` entry for build artifacts (if the project lacks one)**
   What: Check the project root and each module folder for an existing `.gitignore` covering `.build/`, `*.swiftmodule`, `*.swiftdeps`, `*.dia`, `*.d`; add or extend one at the repo root if missing, scoped to SPM build products.
   Why: Prevents ISS-178's root cause (stray build artifacts getting committed) from recurring in this or other modules.

- [ ] 7. **Update the Module Guide**
   What: Add `Source Files` and `Invariants` sections to `1 Setup/Module Guides/5 PDF Viewer/guide.md` per the CLAUDE.md format; correct the initial-load priority description (`.utility`, not `.background`) and the zoom-control description (discrete in/out buttons, not a slider); bump `last_updated`/`last_verified` to the date of this plan's completion; set `status` to `active` if any open issues from this or the companion plan remain, or `stable` once both are resolved.
   Why: ISS-179 — the guide is the source of truth per CLAUDE.md's "Read the Module Guide before touching a module" convention, and it's currently missing required sections and describes behaviour that doesn't match the code.

- [ ] 8. **Add/extend unit tests**
   What: Add a test asserting `InterPanelRouter.open` (or an equivalent event-stream assertion) fires when `PDFViewerPanel`'s open action runs; add a test confirming `document` has no public setter (compile-time, via `@testable import` visibility, not a runtime test) if practical, or document the invariant in the Module Guide if a compile-time test isn't feasible.
   Why: Locks in the router-compliance fix so it can't silently regress back to a direct `appState.openDocument` call.

- [ ] 9. **Manual verification pass**
   What: Run the app; open a PDF via the panel's own Open… button and confirm other panels observe the open event (or confirm via logging); test zoom-from-fit behavior; confirm no visible main-thread stall when rapidly changing pages/zoom on a large document.
   Why: Confirms the fixes work end-to-end in the running app, not just in isolated unit tests.

## Risks and Constraints
- SR-1: step 1 must not have `PDFViewerPanel` reach into another module's implementation — only the `InterPanelRouter` protocol from Foundation 2.1.
- SW-3: step 2's `currentScaleQuery` closure follows the same weak-capture pattern already used for `navigateAction`/`printAction` in `PDFKitView` — do not introduce a strong reference to `PDFView`.
- Step 5 is a deletion of committed files — confirm with `git log --follow` or similar that these are genuinely orphaned artifacts (not, e.g., accidentally-necessary resources) before removing; this is a low-risk but irreversible-in-spirit change worth double-checking before committing.
- Do not let step 4's encapsulation change break existing tests in a way that requires loosening `private(set)` back to `var` — prefer adjusting test setup to go through the public load methods.

## Files Affected
- `5 PDF Viewer/PDFViewerPanel.swift` — `openPanel()`, `statusBar`/`fileSizeString`
- `5 PDF Viewer/PDFViewerViewModel.swift` — `document` visibility, `zoomIn`/`zoomOut`, new `fileSizeString` cache
- `5 PDF Viewer/PDFKitView.swift` — new `currentScaleQuery` binding
- `5 PDF Viewer/Package.swift` — trimmed exclude list
- `5 PDF Viewer/*.d`, `*.dia`, `*.swiftdeps`, `*.swiftmodule` (24 stray files) — deleted
- `.gitignore` (repo root, if missing coverage) — added/extended
- `1 Setup/Module Guides/5 PDF Viewer/guide.md` — Source Files + Invariants sections, drift corrections
- `5 PDF Viewer/Tests/PDFViewerModuleTests.swift` — new test cases

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[5 PDF Viewer] Router compliance, render-path cleanup, and guide drift`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
