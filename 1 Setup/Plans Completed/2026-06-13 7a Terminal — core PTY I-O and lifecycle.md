---
plan: Terminal — core PTY I/O and lifecycle
module: 7 Terminal
created: 2026-06-13
status: implemented
implemented: 2026-06-14
related_issues: ISS-068, ISS-069, ISS-070, ISS-072, ISS-073, ISS-074
split_from: 2026-06-13 7 Terminal PTY hardening.md (deleted 2026-06-14 after split into 7a/7b/7c)
---

> **Split 1 of 3** carved from the original "PTY lifecycle hardening" plan. This plan owns the
> coherent I/O-model rewrite (read path, slave-fd close, write path, back-pressure) plus the
> lifecycle fixes (SIGKILL escalation, self-capture leak). Land this **before** `7b` (controlling
> terminal) and `7c` (hardening), since both build on the launch/teardown path changed here.

## Purpose
Make the Terminal PTY read/write pipeline stable and leak-free under real interactive use:
eliminate the executor-thread starvation from the blocking read loop (ISS-068), the
close-under-blocked-read crash race (ISS-070), the orphaned-shell risk on quit (ISS-072),
unbounded output buffering (ISS-073), blocking PTY writes that wedge the actor (ISS-074), and
the reader/pump self-capture that defeats the leak guard (ISS-069).

## Success Condition
Verified by build + manual exercise of a running terminal:
- `swift build` clean across all packages (no new warnings in module 7).
- Existing `TerminalModuleTests` pass; new tests for EOF teardown and SIGKILL escalation pass.
- `cat` of a large file does not balloon RAM; closing a tab mid-output never crashes (ISS-070, ISS-073).
- Opening and closing 5 terminal tabs in a loop shows no growth in thread count or live
  `TerminalSession`/`TerminalManager` instances (Instruments — ISS-068, ISS-069).
- Quitting the app with a hung shell (one trapping SIGTERM) still terminates within the kill
  timeout (ISS-072).

## Steps

- [x] 1. **Replace the blocking read loop with an event-driven source (ISS-068)**
   What: In `TerminalSession`, replace the `Task(priority:.utility)` `availableData` loop with a
   `DispatchSource.makeReadSource(fileDescriptor:)` (or `FileHandle.readabilityHandler`) on the
   master fd that reads available bytes non-blockingly and yields them into the existing
   `AsyncStream` continuation. Cancel/close the source in `cleanupPTY()`.
   Why: `availableData` blocks a Swift cooperative-pool thread for the session's lifetime;
   multiple idle terminals starve the executor (ISS-068). An event source is the canonical macOS
   PTY read path and removes the blocked thread entirely. This is the documented `DispatchQueue`-
   bridge exception under MR-3.

- [x] 2. **Close the parent's slave fd immediately after launch (ISS-070)**
   What: After `zsh.run()` succeeds, close the parent-side `slaveHandle` (the child holds its own
   dup). Drive stream completion (`continuation.finish()`) from the read source's EOF/`.end` event
   rather than only from `terminationHandler`.
   Why: Holding the slave open prevents the master from ever seeing EOF, forcing teardown to close
   the master fd under a blocked/active reader — the use-after-close race and `availableData`
   exception crash (ISS-070). Closing it converts shell exit into a natural EOF that ends the
   stream cleanly.

- [x] 3. **Bound the output stream and back-pressure the pump (ISS-073)**
   What: Switch `outputStream` off `.unbounded` to a bounded policy sized for terminal bursts,
   and/or coalesce reads + throttle `emu.snapshot()` so the emulator drains at a sane cadence
   instead of per-chunk.
   Why: Unbounded buffering lets a fast producer grow raw `Data` without limit; SR-3 caps only
   parsed scrollback (ISS-073).

- [x] 4. **Make PTY writes non-blocking (ISS-074)**
   What: Route `send(_:)` through a small outbound queue drained by a `DispatchSource` write
   handler (or set the master fd non-blocking and queue on `EAGAIN`), so a full PTY input buffer
   never blocks the actor.
   Why: A blocking `write` wedges the `TerminalSession` actor, queuing `resize`/`terminate` behind
   it so a stuck session can't be killed (ISS-074).

- [x] 5. **Escalate termination to SIGKILL with an exit check (ISS-072)**
   What: In `terminate()`, after SIGTERM poll for actual exit (await `terminationHandler`/
   `isRunning`) up to a timeout (~2 s); if still alive, `kill(pid, SIGKILL)`. Only then
   `cleanupPTY()`. Keep idempotency.
   Why: The fixed 150 ms sleep with no escalation leaks orphaned shells that ignore SIGTERM — the
   zombie case spec 7.5 exists to prevent (ISS-072).

- [x] 6. **Fix the reader/pump self-capture (ISS-069)**
   What: Either re-resolve `self` weakly inside each loop iteration (`guard let self = self else
   { break }` per turn) or convert to a structured design where explicit `terminate()`/`cancel()`
   is the sole teardown and document that the strong capture is intentional. Apply to both the
   `TerminalSession` reader and `TerminalManager.pumpTask`.
   Why: The current `guard let self` outside the loop holds `self` strongly for the loop's life,
   defeating SW-2's leak guard (ISS-069).

- [x] 7. **Re-verify and update the Module Guide**
   What: Run the Success Condition checks; update `1 Setup/Module Guides/7 Terminal/guide.md` so
   the SW-2 invariant and the EOF failure-mode entry match the new reality (true `[weak self]`
   deallocation, EOF-driven stream finish, bounded output, SIGKILL escalation). Set
   `status: active` (PTY work continues in 7b/7c), `last_updated`/`last_verified` to 2026-06-13.
   Why: The guide currently claims behaviour the old code did not have; it must match the fixed code.

## Risks and Constraints
- **Steps 1, 2, 4 change the I/O model together** — land them as one coherent change to avoid an
  intermediate state that mixes blocking reads with early slave close.
- Must stay within SW-1/SR-4: the allowed `DispatchSource` bridge (steps 1, 4) is documented at
  the call site per MR-3.
- No third-party packages (SR-5); all via Darwin POSIX + Dispatch.
- Behaviour-preserving for the emulator/render path — only the session I/O and lifecycle change.
- Does **not** give the shell a controlling terminal — Ctrl-C/resize remain broken until `7b`.
  Does not touch `PTYHandle` reentrancy, the observer race, resize ordering, or shell-integration
  injection — those are `7c`. Does not touch Foundation (module 2).

## Files Affected
- `7 Terminal/TerminalSession.swift` — event-driven read source, early slave close, bounded
  stream, non-blocking writes, SIGKILL escalation, reader self-capture (steps 1–6).
- `7 Terminal/TerminalManager.swift` — pump self-capture fix (step 6).
- `7 Terminal/Tests/TerminalModuleTests.swift` — new tests for EOF teardown and termination escalation.
- `1 Setup/Module Guides/7 Terminal/guide.md` — reconcile invariants/failure modes (step 7).

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly? Yes: all six issues addressed.
- [x] Success Condition verified (ran / tested / confirmed as described above)
- [x] Module Guide updated (`status` + `last_updated`)
- [ ] Changes committed: `[7 Terminal] Core PTY I/O and lifecycle`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
- [x] Mark ISS-068, ISS-069, ISS-070, ISS-072, ISS-073, ISS-074 Resolved in Issues.md with the fix summary
