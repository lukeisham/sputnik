---
plan: Input ordering and PTY teardown hardening
module: 7 Terminal
created: 2026-07-02
status: pending
related_issues: ISS-184, ISS-185, ISS-188
---

## Purpose
Guarantee keystrokes reach the PTY in the order they were typed, and close the two teardown races (activate-after-teardown double-close, deinit zombie) so session start/stop is safe under any timing.

## Success Condition
- A scripted burst of `send` calls (e.g. 200 single-byte sends in a tight loop) arrives at the PTY in exact call order — verifiable with a unit test against a pipe-backed fake or by echoing through a real PTY session in the existing lifecycle test harness.
- Starting a session and terminating it immediately (the ISS-185 race window) never double-closes an fd — exercised in a stress-loop test (start/terminate × N) with no crash or fd corruption.
- Dropping the last reference to a `TerminalSession` with a live shell leaves no zombie process (verify with a lifecycle test that polls `kill(pid, 0)`/`waitpid` semantics, or document the accepted limitation in the guide if full reaping in `deinit` proves impractical).
- All existing `TerminalModuleTests` (including the real-PTY lifecycle tests) still pass.

## Steps

- [ ] 1. **Make `TerminalManager.send` synchronous and ordered**
   What: Replace the per-keystroke `Task { try await sess.send(bytes) }` with a path that preserves call order. Preferred shape: have `TerminalSession` expose a `nonisolated` send that forwards directly to the (thread-safe, queue-confined) `PTYChannel.enqueueWrite` — the channel's serial queue already guarantees ordering — with the channel reference held in a way that's safe to read nonisolated (e.g. set once at start, cleared at teardown, guarded appropriately). If that unsafe-exposure is unpalatable, fall back to a single ordered pipeline: an `AsyncStream<Data>` of outbound bytes consumed by one long-lived task on the session actor, so FIFO order is structural.
   Why: ISS-184 — independent unstructured `Task`s per keystroke have no FIFO guarantee across the actor hop; typing is a hot path and character transposition, however rare, is unacceptable. `enqueueWrite` is already non-blocking, so no caller ever stalls.

- [ ] 2. **Propagate write-failure reporting through the new path**
   What: The current path surfaces PTY write failure (`SputnikError.ptyWriteFailed`) by catching the actor throw in `TerminalManager.send` and setting `sessionEndedMessage`. With a synchronous/streamed send this throw disappears — replace it with an explicit failure signal from `PTYChannel` (e.g. an `onWriteFailure` callback alongside `onEOF`, fired from the unrecoverable-write-error branch of `drainWrites`) that the manager maps to the same `sessionEndedMessage`/`isRunning = false` handling.
   Why: The dead-session restart UX (ISS-110) currently depends on that error path; reordering sends must not silently lose it. Note the existing "unrecoverable write error" branch in `drainWrites` currently swallows failures entirely — this step also fixes that gap.

- [ ] 3. **Guard `PTYChannel.activate()` against prior teardown**
   What: In `activate()`'s queued block, `guard !torndown else { Darwin.close(fd); return }` before creating the read source — wait: teardown's direct-close already closed the fd in that ordering, so the guard should simply `return` without touching the fd. Audit the ownership rule and encode it in comments: exactly one of {teardown-direct-close, read-source-cancel-handler} closes the fd, decided by which side sees the state first, all on the serial queue.
   Why: ISS-185 — today the activate block runs unconditionally; after a teardown-first ordering it resurrects a read source on a closed (possibly reused) fd and its cancel handler double-closes. The fix is one guard, but the ownership comment prevents the next refactor from reintroducing it.

- [ ] 4. **Reap (or explicitly accept) the deinit-path kill**
   What: In `TerminalSession.deinit`, after `kill(pid, SIGKILL)`, reap without blocking deinit: spawn a detached, self-contained reaper (e.g. `DispatchQueue.global(qos: .utility).async { waitpid(pid, nil, 0) }` capturing only the pid value — no self) so the killed child doesn't linger as a zombie. If review concludes even that is unwanted in deinit, instead document in the guide's failure-modes section that the deinit safety net accepts a zombie until app exit, and why.
   Why: ISS-188 — the safety net currently kills but never reaps because it cancels the exit source in the same breath; spec 7.5's "no zombies" invariant should hold even on the leak-recovery path (or the exception should be a documented decision, not an accident).

- [ ] 5. **Add/extend tests**
   What: In `Tests/TerminalModuleTests.swift`: (a) ordered-send test — burst N sends, assert byte order at the receiving end; (b) start/terminate stress loop for the activate/teardown race (mirror the existing `TerminalSessionLifecycleTests` real-PTY pattern, under timeout); (c) deinit-reap test if step 4 implements reaping (spawn, drop the session, poll that the pid is gone).
   Why: All three fixes are timing-sensitive; the module already has a real-PTY lifecycle test harness proven for exactly this class of bug (ISS-070/071/072 tests) — extend it rather than asserting by inspection.

- [ ] 6. **Run the full suite and manual smoke pass**
   What: `swift test` in `7 Terminal/`; manually type fast bursts in the running app, spam-toggle the terminal panel / open-close tabs to exercise rapid start-terminate cycles.
   Why: Ordering and teardown races are exactly the bugs that pass a casual test and fail under load — both automated stress and hands-on abuse are needed.

## Risks and Constraints
- SW-1 / MR-3: step 1's preferred shape widens `PTYChannel`'s role as the documented DispatchQueue exception — keep all new mutable state queue-confined and update the `@unchecked Sendable` justification comment to match (the ISS-115 lesson from module 6: the comment must describe reality).
- SW-2: the deinit reaper (step 4) must capture only the `pid_t` value — never `self` — or it recreates the retain-in-deinit problem the module already solved elsewhere.
- Do not regress the ISS-074 non-blocking write guarantee: no caller of `send` may ever block on a full PTY buffer.
- Steps 1–2 change the `TerminalManager` ↔ `TerminalSession` ↔ `PTYChannel` contract; update the Module Guide's Wiring Details and Invariants sections in the same commit (the guide is unusually detailed for this module and will drift immediately otherwise).
- Independent of the other two Terminal plans; can land in any order relative to them, but all three should land before the click-to-move-cursor feature plan.

## Files Affected
- `7 Terminal/TerminalManager.swift` — `send` path, write-failure handling
- `7 Terminal/TerminalSession.swift` — send exposure, deinit reap
- `7 Terminal/PTYChannel.swift` — activate guard, `onWriteFailure` callback, ownership comments
- `7 Terminal/Tests/TerminalModuleTests.swift` — ordering, race-stress, and reap tests
- `1 Setup/Module Guides/7 Terminal/guide.md` — Wiring Details / Invariants updates

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[7 Terminal] Input ordering and PTY teardown hardening`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
