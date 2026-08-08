---
plan: Terminal production polish — input focus, live resize, profile chrome, API cleanup
module: 7 Terminal
created: 2026-06-10
status: pending
related_issues: ISS-021, ISS-022
depends_on: 2026-06-10 2 Foundation Make project compile.md (app must build to run-test this plan)
---

## Purpose
In order to make this module ready to build bring the 7 Terminal module to production quality: route keyboard focus so a user/agent can type (ISS-021), propagate panel-size changes to both PTY and emulator (ISS-022), replace deprecated/misleading bits, and align the Module Guide with the verified implementation.

## Success Condition
- Click the Terminal panel, type `ls` + Return → the command runs and output appears (keystrokes reach Zsh).
- Resize the window / drag the panel divider, then run `tput cols; tput lines` → reported size tracks the visible grid; `top` (or an agent CLI) reflows to fill the panel instead of staying boxed at 80×24.
- The profile chrome reflects the live profile (font/size) rather than a hardcoded "Default" string.
- `swift build` of the Terminal module emits no deprecation warnings from this module's code.
- `1 Setup/Module Guides/7 Terminal/guide.md` contains no `<!-- assumed -->` markers and documents the focus + resize wiring.
- (Runtime checks require the Foundation compile-fix plan landed first, since the app must build to launch.)

## Steps

- [ ] 1. **Give `TerminalTextView` focus on attach and on click**
   What: In `7 Terminal/TerminalTextView.swift`, override `viewDidMoveToWindow()` to call `window?.makeFirstResponder(self)`, override `mouseDown(with:)` to make itself first responder, and override `acceptsFirstMouse(for:)` → `true`. Keep `acceptsFirstResponder == true`.
   Why: ISS-021 — `keyDown(with:)` only fires for the first responder and nothing promotes the view, so the shell receives no input. Focus belongs in the view (SR-6); AppKit lifecycle callbacks avoid a `DispatchQueue` hop (SW-1/MR-3).

- [ ] 2. **Compute and emit grid dimensions from the view (debounced)**
   What: In `TerminalTextView`, set `postsFrameChangedNotifications = true`, add `public var onResize: ((UInt16, UInt16) -> Void)?`, and on frame change derive `cols = floor(bounds.width / cellWidth)`, `rows = floor(bounds.height / cellHeight)` from cached metrics; guard zero metrics and only fire when the pair changes from the last reported value.
   Why: ISS-022 — the view is the only place that knows the cell metrics, so it must translate points → cells. De-duping prevents PTY spam during a drag.

- [ ] 3. **Forward `onResize` through `TerminalRenderer`; delete dead code**
   What: In `7 Terminal/TerminalRenderer.swift`, set `view.onResize = onResize` in `makeNSView` and refresh it in `updateNSView`. Remove the unused `Coordinator.observer` property and the frame-observation scaffolding it implied.
   Why: ISS-022 — the renderer already receives `onResize` from `TerminalView` but never connects it; the `Coordinator.observer` was declared-but-unassigned, so resize was silently dead (SR-6: remove dead code).

- [ ] 4. **Resize the emulator as well as the PTY**
   What: In `7 Terminal/TerminalManager.swift`, change `resize(cols:rows:)` to call both `session.resize(cols:rows:)` (PTY `TIOCSWINSZ`) and `emulator.resize(cols:rows:)` (already at `TerminalEmulator.swift:94`), then refresh the snapshot. Retain the emulator reference for post-start resizes.
   Why: ISS-022 — resizing only the PTY leaves the emulator frozen at the `cols: 80, rows: 24` from `startSession`, so output still wraps at 80 columns. Both sides must agree.

- [ ] 5. **Seed the real size at session start**
   What: Ensure the first `onResize` from the view drives the initial geometry, so the hardcoded `80×24` in `startSession` is only a transient default; re-emit the current size on session start to avoid a race where the view sizes before the session exists.
   Why: ISS-022 — guarantees the shell starts at the actual panel size rather than relying on a later resize event that may never come.

- [ ] 6. **Replace the deprecated `Process.launch()`**
   What: In `7 Terminal/TerminalSession.swift:106`, switch `try zsh.launch()` to `try zsh.run()` (the non-deprecated spelling); keep the existing `catch` mapping to `SputnikError.processLaunchFailed`.
   Why: Production polish / SR-5 — `launch()` is deprecated; `run()` is the current throwing API and already fits the surrounding error handling.

- [ ] 7. **Make the profile chrome reflect the live profile**
   What: In `7 Terminal/TerminalView.swift`, replace the hardcoded `Text("Profile: Default")` with the resolved profile's font name + size (e.g. `"Menlo 13"`). Full profile-switching UI is out of scope (profiles are read-only from Settings 2.3); this only removes the misleading static label.
   Why: Production polish — the chrome currently claims "Default" regardless of the active profile, which is inaccurate once Settings drives the font/colours.

- [ ] 8. **Update the Module Guide and remove placeholder markers**
   What: In `1 Setup/Module Guides/7 Terminal/guide.md`: delete every `<!-- assumed -->` marker (types are now verified against source), document the focus path (`viewDidMoveToWindow`/`mouseDown` → first responder) and the resize path (view computes cols/rows → `TerminalManager.resize` → PTY + emulator), and bump `last_updated` to 2026-06-10 (`status: active`).
   Why: The guide is the source of truth (Working Conventions) and currently hedges every type with `<!-- assumed -->`; after this work the design is verified and both wiring paths are real.

## Risks and Constraints
- **Build dependency:** the Terminal module cannot link until Foundation compiles, so the *runtime* success checks here require the companion Foundation compile-fix plan to land first (or concurrently). Static/source review of module 7 can proceed independently.
- **Focus stealing:** grabbing first responder in `viewDidMoveToWindow` could pull focus from another panel on launch (2.4 multi-panel layout). If disruptive, fall back to focus-on-`mouseDown` only — verify during testing.
- **Resize feedback loops:** geometry flow must be one-directional (view → session), never session → view; the de-dupe in Step 2 is the guard.
- **No `DispatchQueue` for business logic (SW-1/MR-3):** use AppKit view-lifecycle callbacks and actor hops only.
- **Module boundary:** all changes stay within module 7 — no Foundation edits in this plan (those are the separate compile-fix plan). AI-detection robustness lives in Foundation's `MainAIMonitor` and is therefore explicitly out of scope here.

## Files Affected
- `7 Terminal/TerminalTextView.swift` — first-responder/focus overrides; frame-change → `onResize` emission.
- `7 Terminal/TerminalRenderer.swift` — wire `onResize`; remove dead `Coordinator.observer`.
- `7 Terminal/TerminalManager.swift` — resize emulator alongside PTY; refresh snapshot.
- `7 Terminal/TerminalSession.swift` — `launch()` → `run()`.
- `7 Terminal/TerminalView.swift` — profile chrome reflects live profile.
- `1 Setup/Module Guides/7 Terminal/guide.md` — remove `<!-- assumed -->`; document focus + resize; bump `last_updated`.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (typed a command, resized + confirmed `tput cols/lines`, chrome shows live profile, guide has no `<!-- assumed -->`)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Issues.md: mark ISS-021 and ISS-022 Resolved with a dated note
- [ ] Changes committed: `[7 Terminal] Production polish — input focus and live resize`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
