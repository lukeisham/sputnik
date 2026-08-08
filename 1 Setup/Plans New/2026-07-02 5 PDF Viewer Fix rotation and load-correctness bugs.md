---
plan: Fix rotation and load-correctness bugs
module: 5 PDF Viewer
created: 2026-07-02
status: pending
related_issues: ISS-170, ISS-171, ISS-172, ISS-173
---

## Purpose
Stop the PDF Viewer from silently corrupting page rotation on disk, dropping in-flight document loads on rapid tab switches, cross-contaminating thumbnails between documents, and mis-reloading/mis-diagnosing image documents.

## Success Condition
- Open a scanned PDF with mixed per-page native rotation (or simulate with a multi-page PDF where pages have different `PDFPage.rotation` values on disk) → rotating via the toolbar rotates *relative* to each page's existing orientation, not to a flattened absolute angle.
- Rotate document A 90°, then switch the active tab to document B → B opens with its own native page rotation intact (unchanged from what's on disk).
- Rotate a document and use "Save As…" → the saved file's page rotation matches what was visually rotated, and re-opening a *different*, never-rotated document afterward shows that document's original orientation, not leftover state from A.
- Open a large/slow-loading PDF A, then immediately switch to PDF B before A finishes loading → the viewer ends up showing B (A's late-arriving load is superseded, not raced against B's).
- Scroll rapidly through a thumbnail sidebar while switching documents → no thumbnail from a previously-open document appears under a page index in the currently-open document.
- Switch away from an image tab and back → the image is not silently reloaded from disk on every tab activation (no loading flicker).
- Open an image file sized between the resolver's 20 MB cap and the panel's 500 MB size-check cap → the error message accurately describes an oversized-file rejection, not "not a valid PNG or JPEG file."

## Steps

- [ ] 1. **Make rotation additive against each page's native rotation**
   What: In `PDFKitView.applyRotation`, instead of setting `doc.page(at: i)?.rotation = target` unconditionally, capture each page's *original* rotation once when the document is first assigned (e.g. in `updateNSView` when `pdfView.document` changes, snapshot `page.rotation` per page into the `Coordinator`), then on each rotate apply `originalRotation[i] + target` (mod 360) rather than overwriting with `target` alone.
   Why: ISS-170 — the current absolute-write flattens documents that have legitimate mixed native per-page rotation (common in scanned PDFs) to one uniform angle on the very first user rotate.

- [ ] 2. **Reset rotation tracking state on document change**
   What: In `Coordinator`, reset `lastAppliedRotation` (and the newly-added per-page original-rotation snapshot from step 1) back to their initial/unset state whenever `updateNSView` detects `pdfView.document !== viewModel.document` — i.e. do this in the same branch that currently does `pdfView.document = viewModel.document`, before `applyRotation` runs.
   Why: ISS-170 — without this reset, switching documents after rotating the previous one causes `applyRotation` to force the *new* document's pages to the stale `lastAppliedRotation` value, silently destroying the new document's native orientation the moment it loads (and this corruption is written to disk if the user then does Save As).

- [ ] 3. **Supersede in-flight loads instead of dropping new requests**
   What: In `PDFViewerViewModel`, replace the `guard !isLoading else { return }` early-return in `loadPDF` and `loadImage` with a cancellable-generation pattern: store the in-flight `Task` (or an incrementing `loadGeneration: Int`), and when a new `loadPDF`/`loadImage` call arrives, cancel the previous task (or bump the generation and have the previous task's completion check it's still current before writing `document`/`errorMessage`/`isLoading`).
   Why: ISS-171 — the current guard silently discards a newer load request if an older one is still running, leaving the viewer showing the wrong (stale) document until something else re-triggers a reload.

- [ ] 4. **Guard thumbnail write-back with document identity**
   What: In `PDFViewerViewModel.generateThumbnail`, capture a reference to the current `document` (or a lightweight identity token, e.g. `ObjectIdentifier(document)`) alongside `capturedPage`/`cache` before entering the detached task; in the `await MainActor.run` write-back, check that `self.document` is still the same document (or the token still matches) before calling `cache.setObject`.
   Why: ISS-172 — without an identity check, a thumbnail generation task started for a since-replaced document can write a stale image into the new document's cache slot for the same page index after `removeAllObjects()` has already run for the new document.

- [ ] 5. **Fix the image-document reload guard**
   What: In `PDFViewerPanel.handleActiveDocumentChange`, the `viewModel.document?.documentURL != url` comparison doesn't work for image-backed documents (`documentURL` is always `nil` for those). Track the loaded source `URL` separately in the view model (a `loadedURL: URL?` property set at the end of both `loadPDF` and `loadImage`, alongside/replacing reliance on `document.documentURL`) and compare against that instead, for both PDF and image cases.
   Why: ISS-173 — the current guard causes every tab-switch back to an already-open image to trigger a full reload from disk, when the equivalent PDF case already works correctly.

- [ ] 6. **Distinguish oversized-image rejection from invalid-file rejection**
   What: In `PDFViewerViewModel.loadImage`, after `resolver.resolve(reference:relativeTo:)` returns, check whether the resolver's own size/dimension caps rejected the file (inspect the `resolved` case/associated data for a size-limit signal — check `PreviewImageResolver`'s actual return type in module 9.6 to find the right signal) and set a distinct error message (e.g. "This image exceeds the preview size limit") rather than falling through to the generic "not a valid PNG or JPEG file" message.
   Why: ISS-173 — the current single failure message misdiagnoses an oversized-but-valid image as a corrupt/invalid file, which sends the user down the wrong troubleshooting path.

- [ ] 7. **Add/extend unit tests**
   What: Add test cases to `5 PDF Viewer/Tests/PDFViewerModuleTests.swift` covering: (a) rotation reset on document swap (mock/fake a document change and assert `lastAppliedRotation`/original-rotation state resets), (b) load supersession (start a load, start a second before the first resolves, assert only the second's result is applied), (c) the image reload guard no longer re-triggers `loadImage` for an unchanged URL.
   Why: These are the highest-risk regressions (silent on-disk corruption, wrong document displayed) — regression coverage prevents them from resurfacing.

- [ ] 8. **Manual verification pass**
   What: Run the app; test with a real scanned/mixed-rotation PDF if available (or a synthetic one with per-page rotation set), and manually walk every scenario in the Success Condition section.
   Why: Rotation-on-disk corruption and cross-document state bleed are UI/file-observable behaviours best confirmed by hand per CLAUDE.md's "test the golden path" guidance — unit tests alone won't catch a visually-wrong rotation.

## Risks and Constraints
- SR-1: stay within module 5; step 6 may need to read `PreviewImageResolver`'s return type from module 9 (Resources) but must not modify module 9's implementation — only how PDF Viewer interprets it.
- SR-2: no force-unwraps introduced; all new error paths must produce a user-facing `errorMessage`, not silently fail.
- SW-1: the load-supersession fix (step 3) must stay within structured/Task-based concurrency — no ad-hoc locks or `DispatchQueue` flags.
- Step 1's per-page original-rotation snapshot must not itself leak memory or grow unbounded — it should be sized to the current document's page count and reset (not appended to) on every document change.

## Files Affected
- `5 PDF Viewer/PDFKitView.swift` — `applyRotation`, `Coordinator` (rotation tracking state, document-change reset)
- `5 PDF Viewer/PDFViewerViewModel.swift` — `loadPDF`, `loadImage`, `generateThumbnail`, new `loadedURL`/generation tracking
- `5 PDF Viewer/PDFViewerPanel.swift` — `handleActiveDocumentChange` reload guard
- `5 PDF Viewer/Tests/PDFViewerModuleTests.swift` — new test cases

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[5 PDF Viewer] Fix rotation and load-correctness bugs`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
