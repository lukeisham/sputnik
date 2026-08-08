---
plan: Terminal — controlling terminal (job control, Ctrl-C, resize)
module: 7 Terminal
created: 2026-06-13
status: implemented
implemented: 2026-06-14
related_issues: ISS-071
split_from: 2026-06-13 7 Terminal PTY hardening.md (deleted 2026-06-14 after split into 7a/7b/7c)
---

> **Split 2 of 3** carved from the original "PTY lifecycle hardening" plan. This is the single
> highest-risk change in the Terminal work: it may move the child launch off `Foundation.Process`
> and revise the MR-4 guidance. Isolated into its own plan so it can be prototyped, verified, and
> reverted independently. **Depends on `7a`** (the core I/O model and slave-fd handling), which
> changes the same launch/teardown path — land `7a` first.

## Purpose
Give the Zsh child a controlling terminal so job control, interrupts (Ctrl-C), and resize
signals (SIGWINCH) reach the foreground process group — the one behaviour `Foundation.Process`
cannot provide (ISS-071).

## Success Condition
Verified by build + manual exercise of a running terminal:
- `swift build` clean across all packages (no new warnings in module 7).
- Existing `TerminalModuleTests` pass; any new launch-path tests pass.
- Ctrl-C interrupts a running `sleep 100` (the foreground process dies, the prompt returns).
- Resizing the panel reflows `top`/`vim` (SIGWINCH reaches the foreground process group).
- A backgrounded job (`sleep 100 &`) and `fg`/`bg`/`jobs` behave as in a real terminal.
- No regression to the `7a` I/O path: large-output `cat` still streams, EOF teardown still clean,
  closing a tab mid-output still never crashes.

## Steps

- [x] 1. **Give Zsh a controlling terminal (ISS-071)**
   What: Launch the child so the slave becomes its controlling TTY: either a small `posix_spawn`
   wrapper using `posix_spawn_file_actions` + a `setsid`/`TIOCSCTTY` step, or `forkpty`. Keep
   `executableURL`/env/cwd semantics identical to the current `Process`-based launch. Verify
   Ctrl-C and SIGWINCH reach the foreground process group.
   Why: `Foundation.Process` does not set a controlling terminal, so job control, interrupts, and
   resize signals don't work (ISS-071). This is the one step that may revise the MR-4 "use
   `Process`" guidance.

- [x] 2. **Re-verify the I/O model survives the launch change**
   What: Confirm the early slave-fd close, EOF-driven `continuation.finish()`, and
   `terminationHandler`/exit-detection path from `7a` still hold under the new launch mechanism.
   If moving to `posix_spawn`/`forkpty` removes `Process.terminationHandler`, replace exit
   detection with `waitpid`/`DispatchSource.makeProcessSource(.exit)` and re-run the `7a` SIGKILL
   escalation test.
   Why: Changing the launch primitive can silently break the teardown contract `7a` established;
   the controlling-terminal change must not regress lifecycle correctness.

- [x] 3. **Re-verify and update the Module Guide + Vibe rule**
   What: Run the Success Condition checks. Update `1 Setup/Module Guides/7 Terminal/guide.md`'s
   MR-4/controlling-terminal description to match the new launch path. If the launch moved off
   `Foundation.Process`, update the MR-4 note in `1 Setup/Vibe_Coding_Rules.md` (and the framework
   table in `CLAUDE.md` if it references `Process` for shell spawning) to record the revised
   guidance and the reason. Set guide `status`/`last_updated`/`last_verified` to 2026-06-13.
   Why: This step changes a documented architectural contract; the guides and rules must record it.

## Risks and Constraints
- **This step touches the MR-4/MR-5 contract.** Moving off `Foundation.Process` to
  `posix_spawn`/`forkpty` is the riskiest change in the Terminal work; prototype and verify
  Ctrl-C/resize on a throwaway branch before committing, and update the Vibe rule note if the
  guidance changes.
- **Hard dependency on `7a`.** The slave-fd close, bounded read path, and SIGKILL escalation must
  already be in place; this plan modifies the same launch/teardown code and assumes that baseline.
- Must stay within SW-1/SR-4 and use only Darwin POSIX (`posix_spawn`/`forkpty`/`setsid`/
  `TIOCSCTTY`) — no third-party packages (SR-5).
- Does not touch Foundation (module 2). Behaviour-preserving for the emulator/render path.

## Files Affected
- `7 Terminal/TerminalSession.swift` — controlling-TTY launch; exit detection if `terminationHandler` is replaced.
- `7 Terminal/PTYHandle.swift` — possibly a `posix_spawn`/`forkpty` helper.
- `7 Terminal/Tests/TerminalModuleTests.swift` — launch-path / job-control tests (where testable).
- `1 Setup/Module Guides/7 Terminal/guide.md` — MR-4/controlling-terminal description.
- `1 Setup/Vibe_Coding_Rules.md` and/or `CLAUDE.md` — MR-4 note, only if the launch primitive changed.

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
- [x] Success Condition verified (ran / tested / confirmed as described above)
- [x] Module Guide updated (`status` + `last_updated`); MR-4 rule updated if applicable
- [ ] Changes committed: `[7 Terminal] Controlling terminal — job control, Ctrl-C, resize`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
- [x] Mark ISS-071 Resolved in Issues.md with the fix summary
