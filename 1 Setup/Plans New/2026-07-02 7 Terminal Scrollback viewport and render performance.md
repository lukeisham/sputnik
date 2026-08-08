---
plan: Scrollback viewport and render performance
module: 7 Terminal
created: 2026-07-02
status: pending
related_issues: ISS-180, ISS-186, ISS-187
---

## Purpose
Give the terminal a real scrolling viewport — bottom-anchored on the live grid, scroll-wheel access to scrollback — and cut per-frame draw cost so rendering stays cheap regardless of scrollback depth.

## Success Condition
- With a fresh shell, the prompt is visible at the bottom of the panel; after `cat`-ing a file longer than one screen, the prompt and cursor are *still* visible at the bottom (the live grid is never displaced by scrollback).
- Scrolling up with the scroll wheel/trackpad reveals scrollback history; scrolling back down (or any new output arriving while at the bottom) re-anchors to the live grid. A visual indicator (or simply the cursor's absence) makes it clear when you're viewing history.
- While scrolled up into history, new output does not yank the view to the bottom (standard terminal behaviour: only re-anchor if the user was already at the bottom).
- Drawing only touches visible rows: with 5,000 lines of scrollback, a repaint does work proportional to the panel height, not to 5,000 lines (verify by instrument or a draw-call counter under test).
- A reverse (upward) multi-row drag selection highlights the correct cells on the anchor and end rows.
- Selection, copy (⌘C), and click-position mapping all work identically whether viewing history or the live grid.

## Steps

- [ ] 1. **Introduce a scroll-offset view model on `TerminalTextView`**
   What: Add a `scrollOffsetLines: Int` (0 = anchored at bottom/live grid; N = scrolled N lines up into history) to `TerminalTextView`, an `isAnchoredToBottom` derived flag, and override `scrollWheel(with:)` to adjust the offset (clamped to `[0, scrollback.count]`), calling `needsDisplay`. Decide against `NSScrollView` embedding: the cell grid draws itself and a document-view approach would force a full-height backing view (O(scrollback) layout) — an internal offset is cheaper and keeps the view self-contained. Document that choice at the call site (SW-3-style justification).
   Why: ISS-180 — there is currently no viewport at all; this is the minimal state needed to make scrollback reachable and the live grid anchored.

- [ ] 2. **Rewrite `draw(_:)` to render only the visible line range, bottom-anchored**
   What: Compute `visibleRows = bounds.height / cellHeight`; derive the window of `scrollback + grid` lines to draw from `scrollOffsetLines` such that offset 0 shows the *last* `visibleRows` lines (grid at the bottom, most recent scrollback above it if the grid is shorter than the view). Iterate only that slice; map slice indices → absolute line indices for selection lookups. Draw the cursor only when its absolute row is inside the visible window.
   Why: ISS-180 — fixes both halves: the live grid becomes visible and bottom-anchored, and draw cost becomes O(visible cells) instead of O(all cells ever scrolled).

- [ ] 3. **Re-anchor on new output only when already at the bottom**
   What: In `update(snapshot:profile:)`, if `scrollOffsetLines == 0` keep it 0 (view follows output); if the user has scrolled up, keep their position stable relative to the content (adjust the offset by the number of newly appended scrollback lines so the same historical lines stay on screen).
   Why: Standard terminal UX — output arriving while you're reading history must not yank you to the bottom, and following output at the bottom must stay seamless.

- [ ] 4. **Update coordinate mapping for the viewport**
   What: Rework `cellPosition(for:)` to map a click point through the visible-window offset to an *absolute* (scrollback+grid) row index, so selection and (future) click-features address the correct cells regardless of scroll position. Clamp to the visible window's bounds.
   Why: Selection currently assumes the top-anchored full-content layout; with a viewport, click→cell mapping must account for the scroll offset or selections land on the wrong rows.

- [ ] 5. **Fix reverse-drag selection geometry**
   What: In `selectedCells`, anchor each endpoint's column to its own row: normalise `(start, end)` into `(first, last)` by row (swapping if the drag went upward), then use `first.col` for the first row's start and `last.col` for the last row's end — instead of `min`/`max` of both endpoints' columns.
   Why: ISS-186 — upward drags currently compute wrong column ranges on the first/last rows; this also matters because the upcoming click-features build on this exact code.

- [ ] 6. **Cache style-variant fonts and reduce per-cell allocation**
   What: Cache the four font variants (plain/bold/italic/bold-italic) in `updateMetrics(for:)` (recomputed only on profile change), replacing the per-glyph `NSFontManager` lookup in `styledFont`. Reuse a single attributes dictionary per style-run where practical rather than building a fresh `[NSAttributedString.Key: Any]` per cell; batch consecutive same-style cells in a row into one `NSAttributedString` draw where it doesn't complicate the code.
   Why: ISS-187 — the font-manager lookup per glyph per frame is pure waste; with step 2 bounding the row count, this bounds the per-row cost, keeping full-screen TUI redraws smooth (SR-4).

- [ ] 7. **Add tests where the logic is extractable**
   What: Extract the visible-window computation (offset + content size + view height → line range) and the selection normalisation into pure helper functions (a small `struct` or static functions) and unit-test them: bottom-anchored at offset 0, mid-history windows, offset clamping, reverse-drag normalisation. Drawing itself stays manual-verified.
   Why: The window math is the part that will regress subtly; pure-function extraction makes it testable without AppKit, matching the module's KeyEncoder/ANSIParser testing pattern.

- [ ] 8. **Manual verification pass**
   What: Run the app; verify every Success Condition scenario, including a `cat` of a large file, scrolling during active output, selection while scrolled up, and a vim session (alt screen typically shows no scrollback — confirm the viewport stays anchored and sane entering/leaving it).
   Why: Scroll feel, anchoring behaviour, and render smoothness are experiential — only a hands-on pass confirms them.

## Risks and Constraints
- Depends on the companion plan "Fix emulator crash and UTF-8 correctness bugs" only weakly — they touch different files and can land in either order, but both should land before the click-to-move-cursor feature plan (per the agreed sequencing).
- SR-4: the whole point is bounded draw cost — no step may reintroduce O(total-lines) work per frame (including selection hit-testing, which currently builds a `Set` of every selected cell; if a selection spans thousands of scrollback lines, consider a range-based membership test instead of materialising the set).
- SW-3: stay with the raw `NSView` + internal offset approach; do not wrap in `NSScrollView` without a documented justification (see step 1).
- Selection clear-on-output behaviour (documented in the guide, ISS-059) interacts with step 3: clearing selection on every snapshot while the user is scrolled up reading history may now be more annoying than before — keep existing behaviour in this plan, note it as a possible follow-up; do not silently change it.
- The alt screen should render with the viewport pinned to the live grid (offset forced to 0 while `snapshot` indicates alt-screen content) if scrollback is suppressed there — coordinate with the emulator plan's ISS-189 change.

## Files Affected
- `7 Terminal/TerminalTextView.swift` — viewport state, `scrollWheel`, `draw`, `cellPosition`, `selectedCells`, font caching
- `7 Terminal/Tests/TerminalModuleTests.swift` — visible-window and selection-normalisation tests
- (possibly) `7 Terminal/CellPosition.swift` — if the selection normalisation helper lives beside the type

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[7 Terminal] Scrollback viewport and render performance`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
