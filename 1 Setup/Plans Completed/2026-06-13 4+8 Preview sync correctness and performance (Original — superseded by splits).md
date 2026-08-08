---
plan: Preview sync correctness and performance
module: 4 Markdown Preview / 8 HTML Preview
created: 2026-06-13
status: superseded
related_issues: ISS-085, ISS-086, ISS-087, ISS-088, ISS-089, ISS-090, ISS-091, ISS-092
---

> **Superseded — do not execute this plan directly.** It has been split into three
> smaller, independently-landable plans. Execute those instead:
> - `2026-06-13 8 HTML preview — crash, placeholder, and CSS-injection caching.md` (ISS-085, 086, 092)
> - `2026-06-13 4 Markdown preview — correctness.md` (ISS-087, 088, 089)
> - `2026-06-13 4 Markdown preview — performance housekeeping.md` (ISS-090, 091)
>
> Retained for reference only — the step text below is the source the splits were carved from.

## Purpose
Fix eight correctness and performance defects in the Markdown and HTML live-preview panels
discovered during a review of the editor↔preview sync pipeline. Two are crashes or stale-data
bugs (ISS-086, ISS-089), two are silent rendering failures (ISS-087, ISS-088), one is a
main-thread stutter under scroll sync (ISS-085), and three are lower-priority performance
housekeeping items (ISS-090, ISS-091, ISS-092).

Does **not** overlap with `2026-06-13 3 Editor concurrency and save-safety hardening.md`
(which owns ISS-081–084, including the `throttledLoad` inner-Task removal in
`HTMLPreviewCoordinator`).

## Success Condition
- `swift build` clean across all packages — no new warnings in modules 4 or 8.
- Opening a Markdown file with a local `![alt](img.png)` image shows the image in the preview
  (ISS-087).
- Changing the font-size menu in the Markdown Preview toolbar immediately resizes the
  rendered text (ISS-088).
- Switching from a Markdown document to a plain-text document never flashes the previous
  document's content in the preview panel (ISS-089).
- An HTML file ending with `</head>` and no body can be edited without crashing (ISS-086).
- With scroll sync enabled, scrolling the editor through a 200-line HTML file produces no
  visible stutter on the main thread — verified by Instruments Time Profiler showing
  `htmlByInjectingOverrides` absent from the main-thread hot path during scroll (ISS-085).

## Steps

- [ ] 1. **Fix the `splitHTML` crash on head-only HTML (ISS-086)**
  File: `8 HTML Preview/HTMLPreviewCoordinator.swift:140`
  Change `html[html.startIndex...headEndRange.upperBound]` to
  `html[html.startIndex..<headEndRange.upperBound]`. The closed-range subscript traps when
  `upperBound == endIndex`; the half-open form handles it correctly. Verify with a unit test
  that passes `"<html><head></head>"` (no body) and `"<html><head></head><body></body>"` to
  `splitHTML` and asserts no crash and correct head/body split.

- [ ] 2. **Guard the HTML placeholder reload (ISS-092)**
  File: `8 HTML Preview/HTMLPreviewView.swift` and `8 HTML Preview/HTMLPreviewCoordinator.swift`
  Add `var isShowingPlaceholder: Bool = false` to `HTMLPreviewCoordinator`. In
  `HTMLPreviewView.updateNSView`, before calling `webView.loadHTMLString(placeholderHTML, ...)`,
  guard with `guard !context.coordinator.isShowingPlaceholder else { return }`. Set
  `isShowingPlaceholder = true` after loading and reset it to `false` whenever a real HTML
  session is loaded (at the top of the `guard let session` branch).

- [ ] 3. **Move CSS injection and image rewriting out of the scroll-sync hot path (ISS-085)**
  File: `8 HTML Preview/HTMLPreviewView.swift`
  The problem: `htmlByInjectingOverrides` (O(n) regex) runs on every `updateNSView` call,
  which includes every scroll tick when sync is on.
  Fix: cache the last-injected result in the coordinator alongside the input hash:
  ```swift
  // In HTMLPreviewCoordinator:
  var lastStyledHTML: String = ""
  var lastStyledInputHash: Int = 0
  ```
  In `updateNSView`, compute `let inputHash = session.text.hashValue ^ settings.stableHash`
  (where `stableHash` is a lightweight hash of the two settings properties that affect CSS
  injection — font postscript name + point size + background hex). Only call
  `htmlByInjectingOverrides` when `inputHash != coordinator.lastStyledInputHash`; otherwise
  use `coordinator.lastStyledHTML` directly before calling `throttledLoad`. This reduces the
  hot path under scroll sync to a single integer comparison.
  Note: `stableHash` is a simple computed property on `SettingsStore` (or computed inline)
  combining the font and background properties — no new dependencies required.

- [ ] 4. **Pass `baseDir` to Markdown image renders (ISS-087)**
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
  The `render(markdown:fontScale:)` overload (line 140 of `MarkdownPreviewViewModel.swift`)
  which ignores both `fontScale` and `baseDir` should be removed — it is a footgun. Any
  callers outside the panel should be updated to use `render(markdown:baseDir:)` directly.

- [ ] 5. **Fix font-scale changes bypassed by the string-equality guard (ISS-088)**
  File: `4 Markdown Preview/MarkdownRenderView.swift:261`
  The guard `guard textView.textStorage?.string != renderedString.string else { return }`
  must also pass through when the font or scale has changed. Add a lightweight comparison:
  ```swift
  let desiredFontSize = settings.resolvedMarkdownPreviewFont.pointSize * fontScale
  let currentFontSize = textView.font?.pointSize ?? 0
  guard textView.textStorage?.string != renderedString.string
      || abs(currentFontSize - desiredFontSize) > 0.5
  else { return }
  ```
  This ensures font-scale and settings-font changes always reach the `textView.font = ...`
  assignment below, without triggering full layout for every scroll event.

- [ ] 6. **Cancel in-flight renders on document close/switch (ISS-089)**
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
  In `MarkdownPreviewPanel.handleActiveDocumentChange`, call `viewModel.cancel()` before
  the `viewModel.renderedString = NSAttributedString()` assignment in the non-Markdown/nil
  branches. This ensures a pending 300 ms debounce cannot land stale content after the
  state has been cleared.

- [ ] 7. **Fix scroll restore reliability (ISS-090)** *(low priority — do last)*
  File: `4 Markdown Preview/MarkdownRenderView.swift:286`
  Replace the hard-coded `asyncAfter(deadline: .now() + 0.05)` scroll restore with a layout-
  driven restore. After calling `textStorage.endEditing()`, call:
  ```swift
  textView.layoutManager?.ensureLayout(for: textView.textContainer!)
  ```
  …synchronously, then perform the scroll immediately without a timer. Remove the
  `asyncAfter` block entirely. This guarantees the document height is accurate before the
  scroll offset is applied regardless of document size.
  For the sync-scroll timing issue (fraction marked applied before the async block runs):
  move `context.coordinator.lastSyncScrollFraction = fraction` to inside the async block,
  after the guard that checks `scrollView` is still alive.

- [ ] 8. **Improve block-cache eviction and add hash-collision guard (ISS-091)** *(low priority)*
  File: `4 Markdown Preview/MarkdownPreviewViewModel.swift:172-177`
  Replace total `blockCache.removeAll()` on >500 entries with half-eviction:
  ```swift
  if blockCache.count > 500 {
      let half = blockCache.count / 2
      blockCache = Dictionary(uniqueKeysWithValues: blockCache.dropFirst(half))
  }
  ```
  To guard against hash collisions, change the cache value type to store the source text
  alongside the attributed string:
  ```swift
  private var blockCache: [Int: (text: String, rendered: SendableAttributedString)] = [:]
  ```
  On cache hit, verify `cached.text == block.text` before using the cached result; on
  mismatch, re-render and overwrite.

- [ ] 9. **Re-verify and update Module Guides**
  After all steps pass: update `1 Setup/Module Guides/4 Markdown Preview/guide.md` to
  reflect: (a) `render(markdown:fontScale:)` overload removed; (b) `cancel()` method added;
  (c) scroll restore uses `ensureLayout`; (d) `baseDir` threaded through to image resolver.
  Update `1 Setup/Module Guides/8 HTML Preview/guide.md` to reflect: (a) CSS injection
  cached by input hash; (b) placeholder reload guarded by `isShowingPlaceholder`; (c)
  `splitHTML` crash fixed. Set `status: stable`, `last_updated: 2026-06-13`,
  `last_verified: 2026-06-13` on both.

## Execution Order
Steps 1–2 are independent and safe to do in either order. Step 3 depends on no other step
but changes a hot path — do it after confirming the build is clean. Steps 4–6 are independent
of each other but all touch `MarkdownPreviewPanel` or `MarkdownPreviewViewModel` — do them
in sequence to avoid merge conflicts. Steps 7–8 are low-priority; do them only after 1–6 are
verified. Step 9 is always last.

## Risks and Constraints
- **Step 3 — `stableHash`:** The hash must cover every property of `SettingsStore` that
  flows into `htmlByInjectingOverrides`. Currently that is `resolvedHtmlPreviewFont`
  (postscript name + point size) and `htmlPreviewBackground` (Color). If new settings are
  added to that function later, `stableHash` must be updated too. Add a comment to
  `htmlByInjectingOverrides` listing all inputs that must be represented.
- **Step 4 — removing `render(markdown:fontScale:)`:** Check all call sites with
  `grep -rn "render(markdown:fontScale:"` before removing; there may be callers in tests.
- **Step 7 — `ensureLayout` on large files:** `ensureLayout` is synchronous and can block
  the main thread for very large documents. Gate it behind `!viewModel.isLargeFile`; keep
  the existing `asyncAfter` fallback for large-file mode.
- Does **not** touch `HTMLPreviewCoordinator.throttledLoad`'s inner Task — that is owned by
  the existing ISS-084 plan (step 4 of `2026-06-13 3 Editor concurrency…`).

## Files Affected
- `8 HTML Preview/HTMLPreviewCoordinator.swift` — steps 1, 2, 3.
- `8 HTML Preview/HTMLPreviewView.swift` — steps 2, 3.
- `4 Markdown Preview/MarkdownPreviewPanel.swift` — steps 4, 6.
- `4 Markdown Preview/MarkdownPreviewViewModel.swift` — steps 4, 6, 8.
- `4 Markdown Preview/MarkdownRenderView.swift` — steps 5, 7.
- `1 Setup/Module Guides/4 Markdown Preview/guide.md` — step 9.
- `1 Setup/Module Guides/8 HTML Preview/guide.md` — step 9.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[4 Markdown, 8 HTML] Preview sync correctness and performance`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
- [ ] Mark ISS-085 through ISS-092 Resolved in Issues.md with the fix summary
