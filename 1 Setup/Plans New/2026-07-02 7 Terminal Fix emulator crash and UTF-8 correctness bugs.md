---
plan: Fix emulator crash and UTF-8 correctness bugs
module: 7 Terminal
created: 2026-07-02
status: pending
related_issues: ISS-181, ISS-182, ISS-183, ISS-189
---

## Purpose
Eliminate the two out-of-bounds crash paths in `TerminalEmulator` and make the grid path decode multi-byte UTF-8 correctly, so no shell output — resize timing, erase sequences, or non-ASCII characters — can crash or garble the terminal.

## Success Condition
- Open vim (alt screen), resize the terminal panel, quit vim → no crash; the normal screen restores at the new dimensions with content intact where it fits.
- A program that fills a line to the last column then emits `ESC[1K` (erase to start) → no crash. Reproducible with a scripted byte sequence in a unit test.
- `ls` in a directory with accented/emoji filenames, and a TUI that draws box-drawing characters (e.g. `htop`), render correctly — no mojibake.
- Running `vim`/`less` and scrolling around inside it leaves the scrollback buffer unchanged (alt-screen output not recorded).
- All existing `TerminalModuleTests` still pass; new tests cover each fixed path.

## Steps

- [ ] 1. **Resize the saved normal grid alongside the active grid**
   What: In `TerminalEmulator.resize`, when `inAltScreen` is true, also reshape `altGrid` (the stashed normal screen) to the new dimensions using the same copy-what-fits logic, and clamp `altCursorRow`/`altCursorCol` to the new bounds. Alternatively (simpler and equally safe): reshape whichever grid is stashed at `exitAltScreen` time before restoring it — pick whichever keeps `resize` the single place where dimensions change.
   Why: ISS-181 — restoring an old-dimensioned grid while `cols`/`rows` describe the new size makes the next print/erase index out of bounds and crash.

- [ ] 2. **Clamp erase ranges against the soft-wrap pending cursor position**
   What: In `eraseLine(.toStart)` and `eraseDisplay(.toStart)`, clamp the loop upper bound to `min(cursorCol, cols - 1)` (and audit every other `grid[cursorRow][...]`/`0...cursorCol` access in `apply` for the same `cursorCol == cols` pending state — `eraseDisplay(.toEnd)`'s `cursorCol..<cols` is already safe as an empty range but verify the row loops too).
   Why: ISS-182 — after printing into the last column `cursorCol` legitimately equals `cols`; any inclusive range up to it indexes past the row's end and crashes.

- [ ] 3. **Add UTF-8 accumulation to `ANSIParser`'s ground state**
   What: Give the parser a small UTF-8 assembly buffer: in the ground state, when a byte ≥ 0x80 arrives, accumulate lead + continuation bytes (reusing the classification logic already proven in `IncrementalLineDecoder.incompleteTrailingByteCount`) and emit a single `.print(Character)` once the scalar completes; emit U+FFFD (replacement character) and resync on genuinely malformed sequences. Bytes < 0x80 keep the existing single-byte path. The buffer must persist across `parse(_:)` calls since a code point can straddle two PTY reads.
   Why: ISS-183 — the current byte-at-a-time `.print(Character(Unicode.Scalar(byte)))` turns every multi-byte UTF-8 character into Latin-1 garbage; accented filenames, emoji, and box-drawing characters all render wrong.

- [ ] 4. **Skip scrollback recording while in the alt screen**
   What: In `TerminalEmulator.scrollUpOneLine`, only `scrollback.append(grid[0])` when `inAltScreen` is false (still remove/append grid rows either way so the alt screen scrolls correctly).
   Why: ISS-189 — full-screen program redraws currently pollute scrollback; real terminals never record alt-screen output there.

- [ ] 5. **Add unit tests for each fixed path**
   What: In `Tests/TerminalModuleTests.swift` add: (a) enter alt screen → resize → exit alt screen → feed prints at the new right edge, assert no crash and correct dims; (b) feed bytes filling a row to the last column then `ESC[1K`, assert no crash and correct erasure; (c) feed a multi-byte UTF-8 sequence split across two `parse` calls, assert a single correct `.print(Character)`; feed a malformed sequence, assert resync without crash; (d) alt-screen scrolling leaves `scrollback.lineCount` unchanged.
   Why: These are all byte-sequence-triggerable regressions — exactly what fast, deterministic emulator tests are for; the module's existing test suite already covers this layer well and should grow with it.

- [ ] 6. **Run the full Terminal test suite and a manual smoke pass**
   What: `swift test` in `7 Terminal/`; then run the app and manually exercise vim-resize-quit, unicode `ls`, and an `htop` session.
   Why: The emulator sits under everything the terminal renders; a regression here breaks the whole panel, so both automated and golden-path verification are warranted.

## Risks and Constraints
- SW-1: `TerminalEmulator` stays an actor; all changes are internal to its isolation — no new cross-actor state.
- The UTF-8 accumulator (step 3) adds parser state; it must be bounded (max 3 held bytes, same as `IncrementalLineDecoder`) so a malformed flood cannot grow it (SR-3).
- Step 3 must not regress ANSI escape handling: a 0x1B byte arriving mid-accumulation should flush/discard the partial scalar and enter the escape state — decide and test this explicitly.
- This plan deliberately does not touch rendering (`TerminalTextView`) — that's the companion viewport plan; keep the boundary clean so the two plans can land independently.

## Files Affected
- `7 Terminal/TerminalEmulator.swift` — `resize`, `eraseLine`, `eraseDisplay`, `scrollUpOneLine`, alt-screen handling
- `7 Terminal/ANSIParser.swift` — ground-state UTF-8 accumulation
- `7 Terminal/Tests/TerminalModuleTests.swift` — new test cases

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[7 Terminal] Fix emulator crash and UTF-8 correctness bugs`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
