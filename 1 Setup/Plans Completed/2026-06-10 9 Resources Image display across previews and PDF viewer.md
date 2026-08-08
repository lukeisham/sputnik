---
plan: Display PNG/JPEG across Markdown preview, HTML preview, and the PDF viewer via one shared, size-bounded image resolver
module: 9 Resources (shared) · 4 Markdown Preview · 8 HTML Preview · 5 PDF Viewer · 2 Foundation (routing)
created: 2026-06-10
completed: 2026-06-10
status: complete
related_issues: ISS-046, ISS-047, ISS-048
depends_on: 2026-06-10 2 Foundation Make project build ready.md 
---

## Purpose
In order to be build ready, let users see PNG and JPEG images in all three display surfaces — inline in the Markdown preview, inline in the HTML preview, and as a standalone document in the PDF viewer — through a single shared image-loading utility that enforces a hard size/pixel limit so large images never blow RAM (SR-3).

## Design Decisions (confirmed with user)
- **HTML images:** custom `WKURLSchemeHandler` (streams downsampled bytes), **not** base64 data-URI inlining — keeps the HTML string small and RAM bounded.
- **Markdown images:** keep the `NSTextView` engine and insert `NSTextAttachment`s — preserves the deliberate selection/copy/link design (SW-3). Do **not** switch Markdown to WebView.
- **PDF images:** wrap the image in a single-page `PDFDocument` via `PDFPage(image:)` — reuses the existing zoom/rotate/fit/print controls with no new view code.
- **One core:** all three surfaces resolve and downsample through the same `PreviewImageResolver` in module 9, so the size limit lives in exactly one place (SR-1).

## Success Condition
- A Markdown file containing `![cat](cat.png)` (sibling file) shows the rendered image inline in the Markdown preview; text selection/copy still works around it.
- An HTML file containing `<img src="cat.jpg">` (sibling file) shows the image in the HTML preview; remote `http(s)` images still load; JavaScript stays disabled (ISS-010 unaffected).
- Double-clicking a `.png`/`.jpg`/`.jpeg` in the File Tree opens it in the PDF Viewer panel with working fit-to-width, zoom, and rotate.
- A deliberately huge image (e.g. 8000×8000 or a >20 MB file) does not spike RAM: it either renders downsampled or shows a "too large" placeholder — verified via Activity Monitor / Instruments allocations staying bounded.
- A missing/corrupt image path shows a graceful placeholder, never a crash (SR-2).
- The three affected Module Guides document the image path and bump `last_updated`.

## Shared Limits (single source of truth in `PreviewImageResolver`)
- **Byte cap:** source files over **20 MB** are not read; resolver returns a placeholder descriptor (filename + size).
- **Pixel cap:** decode via ImageIO `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize = 2000` and `kCGImageSourceCreateThumbnailFromImageAlways` — the full-resolution bitmap is never materialised.
- **Formats:** `png`, `jpg`, `jpeg` (the resolver may accept any ImageIO-decodable type; routing in Step 6 gates on these three).

## Steps

- [ ] 1. **Create the shared `PreviewImageResolver` (module 9)**
   What: Add `9 Resources/9.6 Preview Images/PreviewImageResolver.swift`. Public API (all `Sendable`-friendly, heavy work off the main actor):
   - `func resolve(reference: String, relativeTo baseDir: URL) -> ResolvedImage` where `ResolvedImage` is an enum: `.image(downsampled bytes + MIME + pixel size)`, `.tooLarge(name, byteCount)`, `.unsupported`, or `.notFound`.
   - A convenience `func nsImage(...) -> NSImage?` for the Markdown/PDF callers and a `func data(...) -> (Data, mime: String)?` for the HTML scheme handler — both built on one private ImageIO downsample core.
   - Path safety: resolve `reference` against `baseDir`, reject absolute paths and any result that escapes `baseDir` via `..` (standardised-path prefix check). Leave `http(s)`/`data:` references unhandled (caller passes those through untouched).
   Why: ISS-046/047/048 share the same load+limit logic; defining it once honours SR-1 and puts the RAM ceiling (SR-3) in a single audited place.

- [ ] 2. **Wire `9 Resources/Package.swift` for the new source dir**
   What: Confirm `9.6 Preview Images/` is picked up by the existing target sources (no resources to bundle here — it's pure code). Add an explicit `path`/exclusion only if the target layout requires it.
   Why: Keep the module building; the resolver must be importable by modules 4, 5, and 8.

- [ ] 3. **HTML preview — register a `WKURLSchemeHandler` and rewrite local `<img>` (module 8)**
   What: In `8 HTML Preview/`:
   - Add `SputnikImageSchemeHandler.swift` conforming to `WKURLSchemeHandler`; on `start(_:)` it parses the requested URL, calls `PreviewImageResolver.data(...)` against the coordinator's `currentBaseURL`, and responds with the downsampled bytes (or a 1×1 transparent placeholder for `.tooLarge`/`.notFound`). Honour `stop(_:)`.
   - Register the handler for scheme `sputnik-img` on the `WKWebViewConfiguration` in `HTMLPreviewView.makeNSView` ([HTMLPreviewView.swift:127]).
   - In the existing CSS-injection preprocessing (`htmlByInjectingOverrides`, before [HTMLPreviewView.swift:177]), rewrite local `<img src="…">` whose value is a relative/local path to `src="sputnik-img://host/<percent-encoded-relative-path>"`. Leave `http(s)`, protocol-relative, and existing `data:` URIs untouched.
   Why: ISS-047 — `loadHTMLString(baseURL:)` can't read sibling files; a scheme handler streams bytes without granting broad file access and without bloating the HTML string (SR-3). JS stays off, so no regression to ISS-010.

- [ ] 4. **Markdown preview — thread base dir + insert `NSTextAttachment`s (module 4)**
   What:
   - Thread the document's base directory into the render path: `MarkdownPreviewPanel` already observes `appState.activeDocument`; pass `session.url?.deletingLastPathComponent()` into a new `render(markdown:baseDir:)` on `MarkdownPreviewViewModel` (keep the old signature as a thin forwarder).
   - After `AttributedString(markdown:)` parses, run a post-process pass: scan the source for `![alt](path)` image references, and for each local one build an `NSTextAttachment` whose `image` is `PreviewImageResolver.nsImage(...)` (or a placeholder cell for `.tooLarge`/`.notFound`), splicing it into the `NSAttributedString` at the reference's position. Remote `http(s)` refs render as a labelled link (no network fetch in the preview).
   - Do the splice on the existing background `Task(priority: .utility)` and publish the finished `NSAttributedString` back on the main actor; respect the generation guard so stale renders are dropped.
   Why: ISS-046 — the `AttributedString` parser drops images and the `NSTextView` can only show them as attachments; the base dir is currently unavailable to the renderer. Keeps SW-3 (NSTextView for selection) intact.

- [ ] 5. **PDF viewer — add `loadImage(_:)` via `PDFPage(image:)` (module 5)**
   What: In `5 PDF Viewer/PDFViewerViewModel.swift`, add `func loadImage(_ url: URL) async` mirroring `loadPDF(_:)`: reuse the file-size pre-check, call `PreviewImageResolver.nsImage(...)` for a downsampled `NSImage`, wrap it with `PDFPage(image:)` into a one-page `PDFDocument`, and assign to `document`. Reuse the existing error/`isLoading` plumbing; the TOC/thumbnails sidebars degrade naturally to a single page.
   Why: ISS-048 — PDFKit renders images as pages for free, so the whole viewer (zoom/rotate/fit/print) works with one method and no new view code.

- [ ] 6. **Routing — add `FileType.image` and send it to the PDF panel (module 2)**
   What:
   - In `2 Foundation/2.1 Inter-Panel communication/FileType.swift`, add `case image`; map `png`/`jpg`/`jpeg` to `.image` (remove them from the `.binary` bucket at [FileType.swift:24]).
   - Route `.image` to the PDF Viewer panel in `AppInterPanelRouter.open(_:)` / the preview-routing logic so opening an image activates module 5 and calls `loadImage(_:)`. Update the `InterPanelRouter` doc comment that enumerates per-type routing ([InterPanelRouter.swift:25]).
   - Decide gif/heic/tiff/bmp disposition: leave them as `.binary` for now (out of scope) and note it in the guide.
   Why: ISS-048 — images need a `FileType` and a viewer route; `.image` keeps classification self-documenting (SR-1) rather than overloading `.binary`.

- [ ] 7. **Update the three Module Guides**
   What: In `1 Setup/Module Guides/4 Markdown Preview/guide.md`, `…/8 HTML Preview/guide.md`, and `…/5 PDF Viewer/guide.md`: document the image path (resolver → attachment / scheme handler / `PDFPage(image:)`), note the shared 20 MB / 2000 px limits, record the gif/heic deferral, and bump `last_updated` to 2026-06-10. Add a one-line note to the module-9 guide for the new `PreviewImageResolver`.
   Why: Guides are the source of truth (Working Conventions); the image path is a new cross-module design that must be recorded once per affected module.

## Risks and Constraints
- **Build dependency:** runtime checks require the Foundation build-ready plan landed first (the app must launch). Source review of each module can proceed independently.
- **Module boundary:** the resolver is the only shared addition; modules 4/5/8 depend *down* onto module 9, and routing changes are confined to Foundation 2.1 — no lateral module-to-module coupling (SR-1).
- **RAM ceiling is the headline requirement (SR-3):** downsampling must use ImageIO thumbnailing, never `NSImage(contentsOf:)` on the full file followed by a resize — the latter decodes the full bitmap first and defeats the limit. Verify with Instruments.
- **Security (HTML):** the scheme handler must reject `..` path escapes and must not re-enable JS; only the `sputnik-img` scheme is added (ISS-010 stays intact). Keep the handler's response free of redirects.
- **Markdown attachment cost:** attachments hold their `NSImage` in the text storage; the 2000 px cap bounds this, but very image-dense documents should be spot-checked. Generation guard must still drop stale renders so rapid edits don't leak partial attachment passes.
- **PDF single-page UX:** TOC/thumbnails are meaningless for a one-page image — ensure they hide or no-op rather than showing empty chrome.
- **No third-party packages:** ImageIO, PDFKit, WebKit, AppKit only (Vibe SR-5 / macOS Framework Rules).

## Files Affected
- `9 Resources/9.6 Preview Images/PreviewImageResolver.swift` — new shared resolver (load + 20 MB byte cap + ImageIO 2000 px downsample + path-escape guard).
- `9 Resources/Package.swift` — pick up the new source dir if required.
- `8 HTML Preview/SputnikImageSchemeHandler.swift` — new `WKURLSchemeHandler`.
- `8 HTML Preview/HTMLPreviewView.swift` — register scheme; rewrite local `<img>` in preprocessing.
- `4 Markdown Preview/MarkdownPreviewViewModel.swift` — `render(markdown:baseDir:)`; image post-process → `NSTextAttachment`.
- `4 Markdown Preview/MarkdownPreviewPanel.swift` — pass the document base dir into the render call.
- `5 PDF Viewer/PDFViewerViewModel.swift` — `loadImage(_:)` via `PDFPage(image:)`.
- `2 Foundation/2.1 Inter-Panel communication/FileType.swift` — add `.image`; remap png/jpg/jpeg.
- `2 Foundation/2.1 Inter-Panel communication/AppInterPanelRouter.swift` (+ `InterPanelRouter.swift` doc) — route `.image` to module 5.
- `1 Setup/Module Guides/{4 Markdown Preview,8 HTML Preview,5 PDF Viewer}/guide.md` (+ module-9 guide) — document image path; bump `last_updated`.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (Markdown inline image + selection; HTML local + remote image, JS off; image opens in PDF viewer with controls; huge image stays RAM-bounded via Instruments; missing image → placeholder, no crash)
- [ ] Module Guide(s) updated (`status` + `last_updated`) for modules 4, 5, 8, and 9
- [ ] Issues.md: mark ISS-046, ISS-047, ISS-048 Resolved with a dated note
- [ ] Changes committed: `[9 Resources] Shared image resolver; show PNG/JPEG in Markdown, HTML, and PDF`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
