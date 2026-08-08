---
plan: PTY lifecycle hardening
module: 7 Terminal
created: 2026-06-13
status: superseded
related_issues: ISS-068, ISS-069, ISS-070, ISS-071, ISS-072, ISS-073, ISS-074, ISS-075, ISS-076, ISS-077, ISS-078, ISS-079
---

> **Superseded — do not execute this plan directly.** It has been split into three
> smaller, independently-landable plans. Execute those instead:
> - `2026-06-13 7a Terminal — core PTY I-O and lifecycle.md` (ISS-068, 069, 070, 072, 073, 074)
> - `2026-06-13 7b Terminal — controlling terminal.md` (ISS-071)
> - `2026-06-13 7c Terminal — PTY hardening and correctness.md` (ISS-075, 076, 077, 078, 079)
>
> Retained for reference only — the step text below is the source the splits were carved from.

## Purpose
Make the Terminal PTY stack stable, leak-free, and correct under real interactive use — eliminate the executor-thread starvation, the close-under-blocked-read crash race, the missing controlling-terminal (Ctrl-C / resize) defect, and the orphaned-shell risk, so a long-running multi-terminal session behaves like a real terminal without crashing or leaking.

## Success Condition
Verified by build + manual exercise of a running terminal:
- `swift build` clean across all packages (no new warnings in module 7).
- Existing `TerminalModuleTests` pass; new tests for EOF teardown and SIGKILL escalation pass.
- Ctrl-C interrupts a running `sleep 100`; resizing the panel reflows `top`/`vim` (ISS-071).
- `cat` of a large file does not balloon RAM; closing a tab mid-output never crashes (ISS-070, ISS-073).
- Opening and closing 5 terminal tabs in a loop shows no growth in thread count or live `TerminalSession`/`TerminalManager` instances (Instruments — ISS-068, ISS-069).
- Quitting the app with a hung shell (one trapping SIGTERM) still terminates within the kill timeout (ISS-072).

## Steps

- [ ] 1. **Replace the blocking read loop with an event-driven source**
   What: In `TerminalSession`, replace the `Task(priority:.utility)` `availableData` loop with a `DispatchSource.makeReadSource(fileDescriptor:)` (or `FileHandle.readabilityHandler`) on the master fd that reads available bytes non-blockingly and yields them into the existing `AsyncStream` continuation. Cancel/close the source in `cleanupPTY()`.
   Why: `availableData` blocks a Swift cooperative-pool thread for the session's lifetime; multiple idle terminals starve the executor (ISS-068). An event source is the canonical macOS PTY read path and removes the blocked thread entirely. This is the documented `DispatchQueue`-bridge exception under MR-3.

- [ ] 2. **Close the parent's slave fd immediately after launch**
   What: After `zsh.run()` succeeds, close the parent-side `slaveHandle` (the child holds its own dup). Drive stream completion (`continuation.finish()`) from the read source's EOF/`.end` event rather than only from `terminationHandler`.
   Why: Holding the slave open prevents the master from ever seeing EOF, forcing teardown to close the master fd under a blocked/active reader — the use-after-close race and `availableData` exception crash (ISS-070). Closing it converts shell exit into a natural EOF that ends the stream cleanly.

- [ ] 3. **Give Zsh a controlling terminal**
   What: Launch the child so the slave becomes its controlling TTY: either a small `posix_spawn` wrapper using `posix_spawn_file_actions` + a `setsid`/`TIOCSCTTY` step, or `forkpty`. Keep `executableURL`/env/cwd semantics. Verify Ctrl-C and SIGWINCH reach the foreground process group.
   Why: `Foundation.Process` does not set a controlling terminal, so job control, interrupts, and resize signals don't work (ISS-071). This is the one step that may revise the MR-4 "use `Process`" guidance — flag in the guide.

- [ ] 4. **Escalate termination to SIGKILL with an exit check**
   What: In `terminate()`, after SIGTERM poll for actual exit (await `terminationHandler`/`isRunning`) up to a timeout (~2 s); if still alive, `kill(pid, SIGKILL)`. Only then `cleanupPTY()`. Keep idempotency.
   Why: The fixed 150 ms sleep with no escalation leaks orphaned shells that ignore SIGTERM — the zombie case spec 7.5 exists to prevent (ISS-072).

- [ ] 5. **Bound the output stream and back-pressure the pump**
   What: Switch `outputStream` off `.unbounded` to a bounded policy sized for terminal bursts, and/or coalesce reads + throttle `emu.snapshot()` so the emulator drains at a sane cadence instead of per-chunk.
   Why: Unbounded buffering lets a fast producer grow raw `Data` without limit; SR-3 caps only parsed scrollback (ISS-073).

- [ ] 6. **Make PTY writes non-blocking**
   What: Route `send(_:)` through a small outbound queue drained by a `DispatchSource` write handler (or set the master fd non-blocking and queue on `EAGAIN`), so a full PTY input buffer never blocks the actor.
   Why: A blocking `write` wedges the `TerminalSession` actor, queuing `resize`/`terminate` behind it so a stuck session can't be killed (ISS-074).

- [ ] 7. **Fix the reader/pump self-capture**
   What: Either re-resolve `self` weakly inside each loop iteration (`guard let self = self else { break }` per turn) or convert to a structured design where explicit `terminate()`/`cancel()` is the sole teardown and document that the strong capture is intentional. Apply to both `TerminalSession` reader and `TerminalManager.pumpTask`.
   Why: The current `guard let self` outside the loop holds `self` strongly for the loop's life, defeating SW-2's leak guard (ISS-069).

- [ ] 8. **Harden `PTYHandle`**
   What: Use `ptsname_r` into a caller-owned buffer; add a `deinit` (or `closeOnDealloc: true`) so a dropped handle cannot leak the master fd.
   Why: `ptsname` is non-reentrant (concurrent-init race) and the fd leaks if `close()` is ever missed (ISS-075).

- [ ] 9. **Synchronise the observer reference**
   What: Replace `nonisolated(unsafe) weak var aiOutputObserver` with an actor-isolated setter method (or hand it in at `start()`), so it is only touched under actor isolation.
   Why: Cross-actor read/write of the `unsafe` weak var is a real data race (ISS-076).

- [ ] 10. **Serialise resize and decode the observer stream incrementally**
   What: In `TerminalManager.resize`, coalesce to a single in-flight task applying the latest size (cancel/replace prior). In the observer line splitter, use an incremental UTF-8 decoder that carries partial multi-byte sequences across reads.
   Why: Unordered resize tasks can apply a stale grid size (ISS-078); per-chunk `String(data:)` drops text when a code point splits across reads (ISS-079).

- [ ] 11. **Replace timed shell-integration injection with ZDOTDIR (optional, lower priority)**
   What: Write a temp `ZDOTDIR` whose `.zshrc` sources the user's real config then appends the OSC 133 hooks; point the child env at it instead of writing the snippet to stdin after 300 ms.
   Why: The timed stdin injection races slow rc loads and echoes into the first prompt (ISS-077). Can be deferred if scope is tight.

- [ ] 12. **Re-verify and update the Module Guide**
   What: Run the Success Condition checks; update `7 Terminal/guide.md` so the SW-2 invariant, the EOF failure-mode entry, and the MR-4/controlling-terminal description match the new reality; set `status`/`last_updated`/`last_verified`.
   Why: The guide currently claims behaviour (true `[weak self]` deallocation, EOF-driven stream finish) the old code did not have; it must match the fixed code.

## Risks and Constraints
- **Step 3 touches the MR-4/MR-5 contract.** Moving off `Foundation.Process` to `posix_spawn`/`forkpty` is the riskiest change; prototype and verify Ctrl-C/resize before committing, and update the Vibe rule note if the guidance changes. Does not touch Foundation (module 2).
- Steps 1, 2, 6 change the I/O model together — land them as one coherent change to avoid an intermediate state that mixes blocking reads with early slave close.
- Must stay within SW-1/SR-4: the one allowed `DispatchSource` bridge (steps 1, 6) is documented at the call site per MR-3.
- No third-party packages (SR-5); all via Darwin POSIX + Dispatch.
- Behaviour-preserving for the emulator/render path — only the session I/O and lifecycle change.

## Files Affected
- `7 Terminal/TerminalSession.swift` — event-driven read source, early slave close, controlling-TTY launch, SIGKILL escalation, bounded stream, non-blocking writes, isolated observer, incremental decode (steps 1–7, 9, 10).
- `7 Terminal/PTYHandle.swift` — `ptsname_r`, deinit/fd-safety (step 8); possibly a `posix_spawn` helper for step 3.
- `7 Terminal/TerminalManager.swift` — pump self-capture fix, serialised resize (steps 7, 10).
- `7 Terminal/Tests/TerminalModuleTests.swift` — new tests for EOF teardown and termination escalation.
- `1 Setup/Module Guides/7 Terminal/guide.md` — reconcile invariants/failure modes (step 12).

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[7 Terminal] PTY lifecycle hardening`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
- [ ] Mark ISS-068…ISS-079 Resolved in Issues.md with the fix summary
