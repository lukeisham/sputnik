---
plan: Fix data-scrambling and crash bugs
module: 10 ASCII Studio
created: 2026-07-02
status: pending
related_issues: ISS-190, ISS-193, ISS-194
---

## Purpose
Stop the ASCII Studio from silently scrambling opened/library art, crashing on a one-character custom dither ramp, and inserting text into the wrong field.

## Success Condition
- Open a `.txt` file with ragged line widths (some lines shorter than the longest) via "Open .txt…" → the editable canvas shows the art exactly as it appeared in the file, correctly padded, no row-shift.
- Click "Edit" on a Library clip whose lines are not 80 columns wide → the canvas shows the clip correctly, not scrambled.
- Set the ramp style to Custom, type a single character, enable Floyd–Steinberg dither, and trigger a conversion → no crash; the output renders (even if visually degenerate with one character).
- Click into the Library tab's search field, then click "Insert" without ever clicking into the document editor → nothing is inserted into the search field; either the insert is a no-op or it correctly targets the last real editor text view.
- Existing `ASCIIStudioModuleTests` still pass; new tests cover the padding fix and the dither edge case.

## Steps

- [ ] 1. **Fix `ASCIIImageEditor.load` to pad each line individually**
   What: Rewrite `load(_:targetColumns:)` to split the input on newlines first (`string.components(separatedBy: .newlines)`), pad or truncate each line to exactly `targetColumns` characters, then concatenate into the flat grid — instead of filtering out all newlines first and padding only the trailing end of the flat array.
   Why: ISS-190 — the current flatten-then-pad-at-the-end approach silently shifts every row after the first short line, scrambling any non-uniform-width input (which the converter never produces, but opened files and library clips routinely are).

- [ ] 2. **Fix the Library "Edit" button's hardcoded column count**
   What: In `ASCIIStudioLibraryView`'s `clipCard(_:)` "Edit" action, compute the target column count from the clip's actual content (max line length across `clip.content.components(separatedBy: .newlines)`) instead of the hardcoded `targetColumns: 80`, matching the pattern already used in `ASCIIStudioImageView.openTXT()`.
   Why: ISS-190 — hardcoding 80 columns for clips of arbitrary width causes the exact same scrambling as the `openTXT` bug, just via a different entry point.

- [ ] 3. **Guard against a degenerate (≤1 character) ramp in Floyd–Steinberg dithering**
   What: In `ImageToASCIIConverter.applyFloydSteinbergDither`, guard `rampCount > 1` at the top (return the input luminances unchanged, or clamp `levels` to at least 1 in a way that avoids division by zero) before computing `levels = Double(rampCount - 1)`.
   Why: ISS-193 — a one-character custom ramp makes `levels == 0`, producing NaN throughout the luminance array, which then traps in `Int(lum * Double(ramp.count - 1))` in the render loop — a user-reachable crash from ordinary UI interaction (custom ramp field + one character + dither toggle).

- [ ] 4. **Also guard the render-loop character-index computation**
   What: In `convertLuminance`'s and `convertComposite`'s row-rendering loops, defensively clamp/guard `ramp.count > 0` before computing `charIdx` (the ramp should never be empty given `effectiveCharacters`'s fallback, but the NaN path in step 3 shows a similar invariant can be violated at the edges — treat this as defense in depth, not a primary fix).
   Why: SR-2 — no force-unwrap-adjacent crash paths should survive even a second, unanticipated way to reach a degenerate ramp/luminance value.

- [ ] 5. **Make `activeTextView()` verify the responder is the document editor**
   What: In `ASCIIStudioCoordinator.activeTextView()`, don't accept `NSApp.keyWindow?.firstResponder as? NSTextView` unconditionally — check that the responder is (or is backed by) the actual `EditorTextView` type from module 3.1, or otherwise exclude SwiftUI field editors (e.g. by checking the view isn't a descendant of a `NSTextField`'s field-editor container). If a clean type check isn't available across the module boundary without a new dependency, prefer `lastKnownTextView` whenever the current first responder isn't confirmed to be the editor, rather than trusting any arbitrary `NSTextView`.
   Why: ISS-194 — inserting into a stray `NSTextView` field editor (e.g. the Library search field) silently discards the user's intended insert with no error and no visible effect, which is confusing and looks like the button is broken.

- [ ] 6. **Add/extend unit tests**
   What: In `Tests/ASCIIStudioModuleTests.swift` add: (a) `load` with ragged-width multi-line input, assert each row reads back correctly via `asString()`; (b) Floyd–Steinberg dither with a single-character ramp, assert no NaN/crash and a defined (even if degenerate) output; (c) if feasible without a full `NSApp`/window harness, a focused test for the responder-type check logic extracted into a testable helper.
   Why: These are exactly the kind of input-shape edge cases that pass casual manual testing (uniform converter output, multi-character ramps) and only surface with real-world/user-generated input — the module's existing test suite already covers the converter and editor well and should grow with it.

- [ ] 7. **Manual verification pass**
   What: Run the app; open a hand-edited ragged `.txt` file, edit a Library clip, trigger the one-character-dither crash scenario, and test Insert while the Library search field has focus.
   Why: Visual scrambling and insert-target correctness are UI-observable behaviours best confirmed by hand per CLAUDE.md's "test the golden path" guidance.

## Risks and Constraints
- SR-2: no force-unwraps introduced; all new guards must produce a defined, non-crashing result rather than silently corrupting output.
- SR-1: step 5 must not create a new cross-module dependency on Text Editor (module 3) internals beyond what's already implied by the existing `EditorTextView` notification contract (`editorTextViewDidBecomeFirstResponder`) — prefer using that existing contract over reaching into module 3's types directly.
- Keep this plan scoped to correctness/crash fixes; do not fold in the threading/performance issues (companion plan) or the guide update (separate plan) here.

## Files Affected
- `10 ASCII Studio/Sources/ASCIIImageEditor.swift` — `load(_:targetColumns:)`
- `10 ASCII Studio/Sources/ASCIIStudioLibraryView.swift` — "Edit" action column-count computation
- `10 ASCII Studio/Sources/ImageToASCIIConverter.swift` — `applyFloydSteinbergDither`, render-loop guards
- `10 ASCII Studio/Sources/ASCIIStudioCoordinator.swift` — `activeTextView()`
- `10 ASCII Studio/Tests/ASCIIStudioModuleTests.swift` — new test cases

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[10 ASCII Studio] Fix data-scrambling and crash bugs`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
