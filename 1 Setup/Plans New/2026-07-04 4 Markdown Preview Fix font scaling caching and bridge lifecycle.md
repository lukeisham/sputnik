---
plan: Fix font scaling, block-cache eviction, fence splitting, and bridge teardown
module: 4 Markdown Preview
created: 2026-07-04
status: pending
related_issues: ISS-215, ISS-216, ISS-217, ISS-218
---

## Purpose
Correct four rendering- and caching-layer defects in the Markdown preview so that the font-size control actually resizes body text, the block cache and block splitter behave as documented, and the Fit-Width bridge swap can no longer break scroll-position persistence.

## Success Condition
- Changing the Font Size menu (80% / 100% / 120% / 150%) visibly resizes rendered **body** text (not just headings), and does so without a full re-parse.
- Rapidly typing in a large Markdown document no longer triggers a full text-storage rewrite on every `updateNSView` pass when neither content nor font size changed (verified by instrumenting/observing the `updateNSView` guard, or via a test on the guard predicate).
- A document whose fenced code block contains the *other* fence marker (e.g. `~~~` inside a ```` ``` ```` block) splits into the correct top-level blocks (verified by a `splitMarkdownBlocks` unit test).
- Toggling Fit Width repeatedly and then scrolling still persists and restores per-document scroll position (scroll observer remains registered).
- `swift build` and `swift test` pass for the module.

## Steps

- [ ] 1. **Apply the base preview font during rendering, not on the text view**
   What: In the render pipeline (`MarkdownPreviewRenderer` / `parseMarkdownSegment` + `applyKindAttributes`), set a base body font (the resolved preview font) on every run that does not already carry an explicit font from `PresentationIntent` styling, OR have `updateNSView` apply the scaled base font to the whole `textStorage` range *after* `setAttributedString` for ranges lacking a `.font` attribute. Headings/code keep their kind-specific fonts, scaled by `fontScale`.
   Why: ISS-216 — `textView.font` is currently set *before* `setAttributedString`, so the incoming `AttributedString` (body runs have no explicit font) wins and body text never reflects the scale/settings font. Font must be carried by the attributed string or reapplied after the storage swap.

- [ ] 2. **Scale heading/code fonts by `fontScale` consistently**
   What: Thread `fontScale` into `applyKindAttributes` (or apply a uniform post-pass multiplier) so headings and code blocks scale with the same factor as body text, keeping their relative size hierarchy.
   Why: ISS-216 — otherwise only some runs scale, producing inconsistent typography as the user changes zoom.

- [ ] 3. **Make the `updateNSView` change-guard robust to post-replace font readback**
   What: Stop deriving "did the font change?" from `textView.font?.pointSize` after the storage replace. Instead track the last-applied `(contentIdentity, fontScale, settingsFontPointSize)` on the coordinator (or compare against a stored value) and only rewrite storage when one of those actually changed.
   Why: ISS-216 — reading `textView.font` after `setAttributedString` can return the first run's font (e.g. a 24pt heading), making `abs(current - desired) > 0.5` spuriously true and forcing a full rewrite + scroll-restore on every update (SR-4 redundant work).

- [ ] 4. **Evict the oldest block-cache entries, not arbitrary ones**
   What: Replace the `Dictionary.dropFirst(half)` eviction in `MarkdownPreviewViewModel.applyRenderedResult` with an ordering-aware structure — e.g. maintain an insertion/last-used order list (or store an access counter/sequence in the cache value) and drop the least-recently-used half when count exceeds 500.
   Why: ISS-217 — `dropFirst` on a `Dictionary` drops an unordered arbitrary half, contradicting the ISS-091 invariant (documented in the guide) that eviction preserves recently-used entries; today a hot block can be evicted while cold ones survive.

- [ ] 5. **Track fence marker type in `splitMarkdownBlocks`**
   What: In `splitMarkdownBlocks`, when a fence opens, record whether it was ```` ``` ```` or `~~~` and only toggle `inFence` closed on a line whose marker matches the opening marker; ignore the non-matching marker while inside a fence.
   Why: ISS-218 — the current `inFence.toggle()` on either marker lets a `~~~` line inside a ```` ``` ```` block (or vice versa) falsely close fence tracking, mis-splitting the block on enclosed blank lines.

- [ ] 6. **Make the render-view bridge teardown resilient to the Fit Width swap**
   What: Ensure the scroll-observer/token lifecycle is per-`NSScrollView`, not on the shared coordinator in a way the sibling bridge can clobber. Options (pick the minimal correct one): store `scrollObserverToken` and `observedClipView` on the created `NSScrollView` (via associated object or a small owned box) instead of the shared coordinator, OR guard `dismantleNSView` so it only removes the observer if the token still corresponds to the view being dismantled.
   Why: ISS-215 — Fit Width mounts a new bridge that shares one coordinator; if the new `makeNSView` runs before the old `dismantleNSView`, the dismantle nils the *new* view's token and scroll persistence silently dies (SW-2).

- [ ] 7. **Add/extend unit tests**
   What: Add tests to `4 Markdown Preview/Tests/MarkdownPreviewModuleTests.swift` for: (a) `splitMarkdownBlocks` with mixed fence markers (step 5), (b) block-cache eviction keeps the most-recently-used entries (step 4), and (c) the `updateNSView` change-guard predicate returns "no change" when only a heading-first document is re-applied at the same scale (step 3, extract the predicate into a testable pure function if needed).
   Why: Locks in each fix so a future refactor doesn't silently reintroduce the arbitrary eviction, the fence desync, or the redundant rewrite.

- [ ] 8. **Refresh the Module Guide's rendering/caching notes**
   What: In `1 Setup/Module Guides/4 Markdown Preview/guide.md`, correct the eviction description (LRU, not `dropFirst`), the font-application flow (font carried in the attributed string / reapplied post-swap), and the fence-tracking behaviour (partial ISS-219 closeout for the rendering surface).
   Why: The guide currently documents the buggy behaviour as correct (e.g. "half-evicts the oldest entries"), so it must be updated to match the fixed code.

## Risks and Constraints
- **Threading:** all `NSTextView`/`textStorage` mutation stays on `@MainActor` (SW-1); font application inside the render pipeline runs off-main but only builds `NSAttributedString`, which is fine (immutable transfer via `SendableAttributedString`).
- The font fix must not double-apply (once in the string, once on the view) and clobber the kind-specific heading/code fonts — choose one authority for the base font and document it at the call site (SW-3/SW-4).
- Step 6 must not reintroduce the ISS-093 leak: whichever storage location holds the observer token, `dismantleNSView` must still remove it exactly once.
- Shares `MarkdownRenderView.swift` with the minimap plan (ISS-213/214, which also touches `dismantleNSView`/`makeNSView` and `viewModel.scrollView`) — coordinate ordering: land this plan's teardown fix first, then the minimap plan builds its `scrollView` publishing on top.
- No Foundation API changes; stays within module 4.

## Files Affected
- `4 Markdown Preview/MarkdownPreviewRenderer.swift` — base-font application; mixed-fence tracking in `splitMarkdownBlocks`.
- `4 Markdown Preview/MarkdownRenderView.swift` — font applied after storage swap; robust change-guard; per-view observer-token lifecycle.
- `4 Markdown Preview/MarkdownPreviewViewModel.swift` — LRU block-cache eviction.
- `4 Markdown Preview/MarkdownPreviewCoordinator.swift` — (if used) storage for last-applied font/content identity and/or per-view token guard.
- `4 Markdown Preview/Tests/MarkdownPreviewModuleTests.swift` — new/extended tests.
- `1 Setup/Module Guides/4 Markdown Preview/guide.md` — corrected rendering/caching notes.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`) — `1 Setup/Module Guides/4 Markdown Preview/guide.md`
- [ ] Changes committed: `[4 Markdown Preview] Fix font scaling, caching, and bridge lifecycle`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
