---
plan: Markdown preview — correctness
module: 4 Markdown Preview
created: 2026-06-13
status: pending
related_issues: ISS-087, ISS-088, ISS-089
split_from: 2026-06-13 4+8 Preview sync correctness and performance.md (deleted 2026-06-14 after split)
---

> **Split 2 of 3** carved from the original "Preview sync correctness and performance" plan.
> Owns the user-visible Markdown correctness bugs: missing local images, font-scale changes that
> don't take, and stale content flashing on document switch. Independent of the HTML split.
> The lower-priority Markdown performance items are in split 3
> (`2026-06-13 4 Markdown preview — performance housekeeping.md`).

## Purpose
Fix three Markdown-preview correctness defects: local `![alt](img.png)` images not rendering
because `baseDir` is never threaded through (ISS-087), font-size menu changes bypassed by the
string-equality guard so the rendered text never resizes (ISS-088), and the previous document's
content flashing in the preview when switching to a plain-text/nil document (ISS-089).

## Success Condition
- `swift build` clean across all packages — no new warnings in module 4.
- Opening a Markdown file with a local `![alt](img.png)` image shows the image in the preview
  (ISS-087).
- Changing the font-size menu in the Markdown Preview toolbar immediately resizes the rendered
  text (ISS-088).
- Switching from a Markdown document to a plain-text document never flashes the previous
  document's content in the preview panel (ISS-089).

## Steps

- [ ] 1. **Pass `baseDir` to Markdown image renders (ISS-087)**
  Files: `4 Markdown Preview/MarkdownPreviewPanel.swift` (lines 437, 460)
  In `triggerRender(markdown:)`, replace:
  ```swift
  viewModel.render(markdown: markdown, fontScale: viewModel.fontScale)
  ```
  with:
  ```swift
  let baseDir = appState.activeDocument?.url?.deletingLastPathComponent()
  viewModel.render(markdown: markdown, baseDir: baseDir)
  ```
  Do the same in `handleActiveDocumentChange` where `viewModel.render` is called (line 460).
  The `render(markdown:fontScale:)` overload (line 140 of `MarkdownPreviewViewModel.swift`) which
  ignores both `fontScale` and `baseDir` should be removed — it is a footgun. Any callers outside
  the panel should be updated to use `render(markdown:baseDir:)` directly.

- [ ] 2. **Fix font-scale changes bypassed by the string-equality guard (ISS-088)**
  File: `4 Markdown Preview/MarkdownRenderView.swift:261`
  The guard `guard textView.textStorage?.string != renderedString.string else { return }` must
  also pass through when the font or scale has changed. Add a lightweight comparison:
  ```swift
  let desiredFontSize = settings.resolvedMarkdownPreviewFont.pointSize * fontScale
  let currentFontSize = textView.font?.pointSize ?? 0
  guard textView.textStorage?.string != renderedString.string
      || abs(currentFontSize - desiredFontSize) > 0.5
  else { return }
  ```
  This ensures font-scale and settings-font changes always reach the `textView.font = ...`
  assignment below, without triggering full layout for every scroll event.

- [ ] 3. **Cancel in-flight renders on document close/switch (ISS-089)**
  File: `4 Markdown Preview/MarkdownPreviewViewModel.swift` and
  `4 Markdown Preview/MarkdownPreviewPanel.swift`
  Add a public `cancel()` method to `MarkdownPreviewViewModel`:
  ```swift
  public func cancel() {
      renderGeneration &+= 1   // invalidates any pending generation
      renderThrottle.cancel()
      isRendering = false
  }
  ```
  In `MarkdownPreviewPanel.handleActiveDocumentChange`, call `viewModel.cancel()` before the
  `viewModel.renderedString = NSAttributedString()` assignment in the non-Markdown/nil branches.
  This ensures a pending 300 ms debounce cannot land stale content after the state has been cleared.

- [ ] 4. **Re-verify and update the Module Guide**
  After steps 1–3 pass, update `1 Setup/Module Guides/4 Markdown Preview/guide.md` to reflect:
  (a) `render(markdown:fontScale:)` overload removed; (b) `cancel()` method added; (c) `baseDir`
  threaded through to the image resolver. Set `status: active` (perf housekeeping still pending in
  split 3) or `stable` if split 3 has already landed; `last_updated: 2026-06-13`,
  `last_verified: 2026-06-13`.

## Execution Order
Steps 1–3 are independent of each other but all touch `MarkdownPreviewPanel` or
`MarkdownPreviewViewModel` — do them in sequence to avoid merge conflicts. Step 4 is always last.

## Risks and Constraints
- **Step 1 — removing `render(markdown:fontScale:)`:** Check all call sites with
  `grep -rn "render(markdown:fontScale:"` before removing; there may be callers in tests.
- Coordinate with split 3 (`Markdown preview — performance housekeeping`): both edit
  `MarkdownRenderView.swift` and `MarkdownPreviewViewModel.swift`. Landing this split first is
  recommended (correctness before housekeeping); if both are in flight, sequence the commits.

## Files Affected
- `4 Markdown Preview/MarkdownPreviewPanel.swift` — steps 1, 3.
- `4 Markdown Preview/MarkdownPreviewViewModel.swift` — steps 1, 3.
- `4 Markdown Preview/MarkdownRenderView.swift` — step 2.
- `1 Setup/Module Guides/4 Markdown Preview/guide.md` — step 4.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide updated (`status` + `last_updated`)
- [ ] Changes committed: `[4 Markdown] Preview correctness — images, font scale, stale content`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
- [ ] Mark ISS-087, ISS-088, ISS-089 Resolved in Issues.md with the fix summary
