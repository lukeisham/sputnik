---
plan: Markdown preview — performance housekeeping
module: 4 Markdown Preview
created: 2026-06-13
status: pending
related_issues: ISS-090, ISS-091
split_from: 2026-06-13 4+8 Preview sync correctness and performance.md (deleted 2026-06-14 after split)
---

> **Split 3 of 3** carved from the original "Preview sync correctness and performance" plan.
> These are the two **lower-priority** performance/housekeeping items the original explicitly
> deferred to last. Do this split only after the correctness work in split 2
> (`2026-06-13 4 Markdown preview — correctness.md`) is verified — both edit the same files.

## Purpose
Two lower-priority robustness/performance improvements in the Markdown preview: make scroll
restore deterministic rather than timer-based (ISS-090), and bound the block render cache with
half-eviction plus a hash-collision guard (ISS-091).

## Success Condition
- `swift build` clean across all packages — no new warnings in module 4.
- Scroll position restores correctly after a re-render regardless of document size, with no
  visible jump, and without depending on a fixed `asyncAfter` delay (ISS-090).
- Rendering a document with >500 distinct blocks keeps the block cache bounded (half-evicts rather
  than fully clearing) and never renders the wrong block on a hash collision (ISS-091).
- The correctness behaviour from split 2 is unchanged (images, font scale, no stale-content flash).

## Steps

- [ ] 1. **Fix scroll restore reliability (ISS-090)**
  File: `4 Markdown Preview/MarkdownRenderView.swift:286`
  Replace the hard-coded `asyncAfter(deadline: .now() + 0.05)` scroll restore with a layout-driven
  restore. After calling `textStorage.endEditing()`, call:
  ```swift
  textView.layoutManager?.ensureLayout(for: textView.textContainer!)
  ```
  …synchronously, then perform the scroll immediately without a timer. Remove the `asyncAfter`
  block entirely. This guarantees the document height is accurate before the scroll offset is
  applied regardless of document size.
  For the sync-scroll timing issue (fraction marked applied before the async block runs): move
  `context.coordinator.lastSyncScrollFraction = fraction` to inside the async block, after the
  guard that checks `scrollView` is still alive.

- [ ] 2. **Improve block-cache eviction and add hash-collision guard (ISS-091)**
  File: `4 Markdown Preview/MarkdownPreviewViewModel.swift:172-177`
  Replace total `blockCache.removeAll()` on >500 entries with half-eviction:
  ```swift
  if blockCache.count > 500 {
      let half = blockCache.count / 2
      blockCache = Dictionary(uniqueKeysWithValues: blockCache.dropFirst(half))
  }
  ```
  To guard against hash collisions, change the cache value type to store the source text alongside
  the attributed string:
  ```swift
  private var blockCache: [Int: (text: String, rendered: SendableAttributedString)] = [:]
  ```
  On cache hit, verify `cached.text == block.text` before using the cached result; on mismatch,
  re-render and overwrite.

- [ ] 3. **Re-verify and update the Module Guide**
  After steps 1–2 pass, update `1 Setup/Module Guides/4 Markdown Preview/guide.md` to reflect:
  (a) scroll restore uses `ensureLayout` rather than a timer; (b) block cache uses half-eviction
  with a collision guard. Set `status: stable`, `last_updated: 2026-06-13`,
  `last_verified: 2026-06-13` (assuming split 2 has also landed).

## Risks and Constraints
- **Step 1 — `ensureLayout` on large files:** `ensureLayout` is synchronous and can block the main
  thread for very large documents. Gate it behind `!viewModel.isLargeFile`; keep the existing
  `asyncAfter` fallback for large-file mode.
- **Depends on split 2.** This split edits `MarkdownRenderView.swift` and
  `MarkdownPreviewViewModel.swift`, the same files split 2 touches. Land split 2 first and rebase
  this on top to avoid merge conflicts.

## Files Affected
- `4 Markdown Preview/MarkdownRenderView.swift` — step 1.
- `4 Markdown Preview/MarkdownPreviewViewModel.swift` — step 2.
- `1 Setup/Module Guides/4 Markdown Preview/guide.md` — step 3.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide updated (`status` + `last_updated`)
- [ ] Changes committed: `[4 Markdown] Preview performance housekeeping — scroll restore, block cache`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
- [ ] Mark ISS-090, ISS-091 Resolved in Issues.md with the fix summary
