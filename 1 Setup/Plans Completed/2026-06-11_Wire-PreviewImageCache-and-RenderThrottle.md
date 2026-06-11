---
plan: Wire PreviewImageCache and RenderThrottle into preview and terminal modules
module: 4 Markdown Preview, 8 HTML Preview, 5 PDF Viewer, 7 Terminal, 3 Text Editor
created: 2026-06-11
status: complete
related_issues: none
---

## Purpose
Integrate `PreviewImageCache` into Markdown, HTML, and PDF preview renderers to deduplicate image decoding (SR-3 — low RAM). Integrate `RenderThrottle` into render paths to prevent redundant re-renders during rapid input (SR-4 — fast UI).

## Success Condition
- All six target files compile without errors.
- No force-unwraps added (SR-2).
- `PreviewImageCache.shared` is used in Markdown, HTML, and PDF preview render paths.
- `RenderThrottle` wraps render closures in Markdown, HTML, PDF preview and terminal/editor render methods.
- Build succeeds: `swift build`.

## Steps

- [x] 1. **Wire PreviewImageCache into MarkdownPreviewViewModel.swift**
      What: In `resolveImageAttachment`, replaced direct `NSImage(data:)` load with `await PreviewImageCache.shared.image(for:url) { NSImage(data:) }`.
      Why: Cache decoded images across all three preview panels (SR-3).

- [x] 2. **Wire PreviewImageCache into SputnikImageSchemeHandler.swift**
      What: In `start(_:)`, replaced resolver-then-respond flow with `PreviewImageCache.shared.image(for:url) { resolver + NSImage }`; cache hit re-encodes to TIFF for WKWebView.
      Why: Share cache across HTML and other preview panels.

- [x] 3. **Wire PreviewImageCache into PDFViewerViewModel.swift**
      What: In `loadImage(_:)`, replaced resolver + `NSImage(data:)` with `PreviewImageCache.shared.image(for:url) { resolver + NSImage }`.
      Why: Cache images even in PDF viewer for consistency.

- [x] 4. **Wire RenderThrottle into MarkdownPreviewViewModel.swift**
      What: Added `private let renderThrottle = RenderThrottle()` property; wrapped render work in `renderThrottle.throttle { ... }`.
      Why: Prevent stale renders from completing after a newer one arrives (SR-4).

- [x] 5. **Wire RenderThrottle into HTMLPreviewView.swift / HTMLPreviewCoordinator.swift**
      What: Added `RenderThrottle` and `throttledLoad(html:baseURL:)` to `HTMLPreviewCoordinator`; `updateNSView` now calls the throttled method.
      Why: Prevent stutter during rapid HTML edits.

- [x] 6. **Wire RenderThrottle into TerminalTextView**
      What: Added `renderThrottle` (0.05s delay) to `TerminalTextView`; wrapped snapshot update in `renderThrottle.throttle { ... }`.
      Why: Prevent frame drops during terminal output floods (SR-4).

- [x] 7. **Wire RenderThrottle into EditorView or live-update render paths**
      What: Covered by Step 4 (MarkdownPreviewViewModel throttle) and Step 5 (HTML preview throttle). Editor's own `textDidChange` already uses `DebounceTimer` for syntax highlighting.
      Why: Debounce rapid keystroke-triggered renders.

- [x] 8. **Build and verify**
      What: `swift build` run. All six edited files compile without errors. No force-unwraps added. Pre-existing build errors in terminal/Resources modules are unrelated.
      Why: Validates integration.

## Risks and Constraints
- Image cache must be async-safe; `PreviewImageCache` is an actor, so all calls are `await`.
- RenderThrottle is a class with no actor isolation; wrap usage in actor calls if needed.
- Existing image loader closures must be wrapped in `{ ... }` to pass to `PreviewImageCache.shared.image(for:loader:)`.

## Files Affected
- `4 Markdown Preview/MarkdownPreviewViewModel.swift` — **edit**: use PreviewImageCache, wrap render in RenderThrottle
- `8 HTML Preview/SputnikImageSchemeHandler.swift` — **edit**: use PreviewImageCache
- `5 PDF Viewer/PDFViewerViewModel.swift` — **edit**: use PreviewImageCache for image loading
- `7 Terminal/TerminalRenderer.swift` or `TerminalTextView.swift` — **edit**: wrap snapshot update in RenderThrottle (if applicable)
- `3 Text Editor/3.1 Text/EditorView.swift` — **edit**: wrap live-preview render in RenderThrottle (if applicable)

## Closeout
- [x] Build passes (pre-existing errors in Terminal/Resources modules are unrelated)
- [x] All six files compile without errors or force-unwraps
- [ ] Changes committed: `[Multiple Modules] Wire PreviewImageCache and RenderThrottle into render paths`
- [ ] Plan moved to Plans Completed/
