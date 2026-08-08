---
plan: Bring Module Guide in line with code
module: 10 ASCII Studio
created: 2026-07-02
status: pending
related_issues: ISS-198
---

## Purpose
Update the Module Guide to reflect the already-committed multi-file view split (`ASCIIStudioModel`/`ASCIIStudioImageView`/`ASCIIStudioLibraryView`) and correct its stated library resource path, so the guide is once again a trustworthy source of truth for this module.

## Success Condition
- `guide.md`'s Source Files table lists `ASCIIStudioModel.swift`, `ASCIIStudioImageView.swift`, and `ASCIIStudioLibraryView.swift` as separate entries with accurate responsibilities, and no longer describes `ASCIIStudioView.swift` as owning all `@State` directly.
- The guide's Diagram and Technical Summary sections describe the actual current composition (`ASCIIStudioView` as a thin tab-switching coordinator; `ASCIIStudioModel` as the shared `@Observable` state; the two tab views as consumers).
- The guide's library-path description matches the verified actual bundle path (`9.1 ASCII Library/<category>` — confirmed present under `9 Resources/9.1 ASCII Library/` in this repo) rather than the previously stated `Resources/ASCIILibrary/<category>/`.
- `last_updated` and `last_verified` are bumped to the date this plan completes; `status` reflects whether the companion bug-fix/feature plans for this module have also landed (`active` if any remain open, `stable` only once all are resolved).
- The three companion plans for this module (data-scrambling/crash fixes, threading/render performance, range selection) each still perform their own guide touch-ups for anything they change beyond what's captured here — this plan's job is to fix the *existing* drift, not preemptively describe unmerged work.

## Steps

- [ ] 1. **Re-read the current source files against the guide, file by file**
   What: Go through `guide.md`'s Source Files table and Technical Summary line by line against the actual current contents of `ASCIIStudioView.swift`, `ASCIIStudioModel.swift`, `ASCIIStudioImageView.swift`, and `ASCIIStudioLibraryView.swift` (all read in this review), noting every claim that no longer matches.
   Why: The guide predates an uncommitted refactor that split one ~700-line view into four files — a mechanical diff-and-correct pass, not a rewrite, is the right scope here.

- [ ] 2. **Rewrite the Source Files table**
   What: Add rows for `ASCIIStudioModel.swift` ("`@MainActor @Observable` class — owns all `@State` for conversion settings, editor tab selection, library search, alert state; holds the `ASCIILibraryBrowser` instance"), `ASCIIStudioImageView.swift` ("Image → ASCII tab — action bar, conversion controls, adjustments disclosure, edit toolbar, canvas area; owns import/export/regenerate actions"), and `ASCIIStudioLibraryView.swift` ("Library tab — category picker, search, clip grid, insert/edit actions"); update the `ASCIIStudioView.swift` row to describe it as a thin coordinator that owns `imageEditor`'s lifecycle, switches tabs, and presents the two shared alerts.
   Why: ISS-198 — the table currently only lists the pre-refactor monolithic `ASCIIStudioView.swift` and misattributes ownership of `@State`.

- [ ] 3. **Update the Diagram section**
   What: Adjust the ASCII diagram's implied file structure (or add a short note beneath it) reflecting the four-file composition, without needing to redraw the whole panel layout diagram — the visual layout hasn't changed, only its code organization.
   Why: Keep the diagram accurate without over-engineering a section that's mostly about the *visual* panel, which is unaffected by the refactor.

- [ ] 4. **Correct the library resource path**
   What: Update every mention of `Resources/ASCIILibrary/<category>/` in the guide (Source Files table and Technical Summary's "Library source of truth" note) to `9 Resources/9.1 ASCII Library/<category>/`, matching `ASCIILibraryBrowser.loadClips`'s actual path construction (`Bundle.resourcesModule.bundleURL.appendingPathComponent("9.1 ASCII Library").appendingPathComponent(category.rawValue)`), which was verified against the real directory in this repo.
   Why: ISS-198 — this path mismatch matters more than a typical doc typo: if it had been the code that was wrong instead of the guide, every library category would silently show empty (the code's own documented degrade-gracefully failure mode) with no error surfaced to the user.

- [ ] 5. **Update the Key Types list in Technical Summary**
   What: Add `ASCIIStudioModel` as a documented key type (state ownership, `@Observable`/`@MainActor`), and adjust the existing `ASCIIStudioView` entry to match its now-reduced coordinator role.
   Why: Completeness — the Key Types list is meant to be a reliable map of what owns what; a reader currently has no guide-level indication `ASCIIStudioModel` exists.

- [ ] 6. **Cross-check the Invariants section still holds**
   What: Re-verify each existing invariant bullet against current code (e.g. "`ImageToASCIIConverter.convert` runs on a non-`@MainActor` background Task" — currently **false** per ISS-191, tracked in the companion threading plan). Where an invariant is currently violated by a known, already-logged bug, leave the invariant statement as-is (it describes the *intended* design) but do not claim `last_verified` covers it as true today — this plan documents structure, not bug status; the companion plans update `status`/invariant-truth once their fixes land.
   Why: Avoid this guide-alignment plan silently asserting something is fixed when it isn't — that would just move the drift from "structure" to "invariant accuracy."

- [ ] 7. **Bump metadata and finalize**
   What: Set `last_updated` and `last_verified` to this plan's completion date; set `status` to `active` (companion plans still open) or `stable` if this plan happens to land after all three companion plans are already complete.
   Why: Keeps the guide's own metadata honest about when it was last checked against reality, per the Module Guide Format's `last_verified` convention.

## Risks and Constraints
- This is a documentation-only plan — no source files change. Verify nothing in `10 ASCII Studio/Sources/` is touched at closeout.
- Do not describe the not-yet-implemented range-selection feature (companion plan) as if it exists — describe the *current* code honestly, including its dead-code "Select" button, unless that plan has already landed first.
- Keep edits surgical: use targeted replacements against the specific stale claims identified in step 1, not a full rewrite of the guide (per CLAUDE.md's general preference for minimal, targeted diffs).

## Files Affected
- `1 Setup/Module Guides/10 ASCII Studio/guide.md` — Source Files table, Diagram note, Technical Summary (Key Types, library source-of-truth path), metadata

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`) — this plan's entire deliverable
- [ ] Changes committed: `[10 ASCII Studio] Bring Module Guide in line with code`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
