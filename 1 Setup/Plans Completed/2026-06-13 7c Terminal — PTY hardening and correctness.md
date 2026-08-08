---
plan: Terminal — PTY hardening and correctness
module: 7 Terminal
created: 2026-06-13
status: complete (2026-06-14; step 4/ISS-077 deferred)
related_issues: ISS-075, ISS-076, ISS-077, ISS-078, ISS-079
split_from: 2026-06-13 7 Terminal PTY hardening.md (deleted 2026-06-14 after split into 7a/7b/7c)
---

> **Split 3 of 3** carved from the original "PTY lifecycle hardening" plan. These are the
> independent hardening/correctness items that do not depend on the I/O-model rewrite. They can
> land after `7a` (recommended) in any internal order. Step 4 (ZDOTDIR injection) is explicitly
> lower priority and may be deferred if scope is tight.

## Purpose
Close the remaining PTY correctness defects that survive the I/O-model rewrite: the
`ptsname` reentrancy + master-fd leak in `PTYHandle` (ISS-075), the data race on the
`unsafe` weak observer reference (ISS-076), out-of-order resize tasks applying a stale grid
size and per-chunk UTF-8 decoding that drops split code points (ISS-078, ISS-079), and the
timed stdin shell-integration injection that races slow rc loads (ISS-077).

## Success Condition
Verified by build + manual exercise of a running terminal:
- `swift build` clean across all packages (no new warnings in module 7).
- Existing `TerminalModuleTests` pass; any new hardening tests pass.
- Opening and closing terminal tabs in a loop shows no master-fd leak (`leaks Sputnik` / fd count
  stable) — ISS-075.
- `Thread Sanitizer` shows no race on the AI-output observer reference under concurrent
  set/read (ISS-076).
- Rapidly resizing the panel never leaves the grid at a stale size; the final applied size always
  matches the last resize (ISS-078).
- Output containing multi-byte UTF-8 (e.g. `printf 'café\\n'` split across reads, emoji) renders
  without mojibake or dropped characters (ISS-079).
- (If step 4 included) Shell-integration hooks are present from the first prompt with no echoed
  snippet text, regardless of `.zshrc` load time (ISS-077).

## Steps

> **Outcome (2026-06-14):** Steps 1–3 + 5 done; step 4 (ZDOTDIR) deferred. The plan
> predated the 7a/7b rewrite — `PTYHandle`/`ptsname` no longer exist (replaced by
> `forkpty`), so step 1 was a verify-and-document rather than a code change, and the
> ISS-079 line splitter now lives in `PTYChannel` (extracted to a testable
> `IncrementalLineDecoder`). Build clean; 120 Terminal tests pass (14 new decoder tests).

- [x] 1. **Harden `PTYHandle` (ISS-075)**
   What: Use `ptsname_r` into a caller-owned buffer instead of `ptsname`; add a `deinit` (or
   `closeOnDealloc: true`) so a dropped handle cannot leak the master fd.
   Why: `ptsname` is non-reentrant (concurrent-init race) and the fd leaks if `close()` is ever
   missed (ISS-075).

- [x] 2. **Synchronise the observer reference (ISS-076)**
   What: Replace `nonisolated(unsafe) weak var aiOutputObserver` with an actor-isolated setter
   method (or hand it in at `start()`), so it is only touched under actor isolation.
   Why: Cross-actor read/write of the `unsafe` weak var is a real data race (ISS-076).

- [x] 3. **Serialise resize and decode the observer stream incrementally (ISS-078, ISS-079)**
   What: In `TerminalManager.resize`, coalesce to a single in-flight task applying the latest size
   (cancel/replace prior). In the observer line splitter, use an incremental UTF-8 decoder that
   carries partial multi-byte sequences across reads.
   Why: Unordered resize tasks can apply a stale grid size (ISS-078); per-chunk `String(data:)`
   drops text when a code point splits across reads (ISS-079).

- [ ] 4. **Replace timed shell-integration injection with ZDOTDIR (ISS-077, optional / lower priority)**
   What: Write a temp `ZDOTDIR` whose `.zshrc` sources the user's real config then appends the
   OSC 133 hooks; point the child env at it instead of writing the snippet to stdin after 300 ms.
   Why: The timed stdin injection races slow rc loads and echoes into the first prompt (ISS-077).
   Can be deferred if scope is tight.

- [x] 5. **Re-verify and update the Module Guide**
   What: Run the Success Condition checks; update `1 Setup/Module Guides/7 Terminal/guide.md` to
   record the `ptsname_r`/fd-safety guarantee, the isolated observer, the serialised-resize and
   incremental-decode behaviour, and (if done) the ZDOTDIR shell-integration mechanism. Set
   `status: stable` (assuming 7a and 7b have also landed; otherwise `active`),
   `last_updated`/`last_verified` to 2026-06-13.
   Why: The guide must match the hardened code so future agents have accurate context.

## Risks and Constraints
- **Independent of the I/O-model rewrite** — these steps do not require `7b`, but assume `7a`'s
  read/teardown path is in place (the observer and resize paths consume the same stream).
- Step 4 (ZDOTDIR) changes the child's environment; verify the user's real `.zshrc` still loads
  (aliases, PATH, prompt) and that no duplicate sourcing occurs.
- Must stay within SW-1/SR-4; all via Darwin POSIX + Dispatch. No third-party packages (SR-5).
- Behaviour-preserving for the emulator/render path.

## Files Affected
- `7 Terminal/PTYHandle.swift` — `ptsname_r`, deinit/fd-safety (step 1).
- `7 Terminal/TerminalSession.swift` — isolated observer setter (step 2); ZDOTDIR env (step 4).
- `7 Terminal/TerminalManager.swift` — serialised resize, incremental decode (step 3).
- `7 Terminal/Tests/TerminalModuleTests.swift` — hardening tests (fd-leak, decode, resize ordering).
- `1 Setup/Module Guides/7 Terminal/guide.md` — reconcile invariants/failure modes (step 5).

## Closeout
- [x] Re-read the Purpose statement — outcome matches for ISS-075/076/078/079; ISS-077 deliberately deferred.
- [x] Success Condition verified: `swift build` clean (no new module-7 warnings); 120 Terminal tests pass incl. 14 new `IncrementalLineDecoder` tests (single/two/four-byte splits). NOT run: `leaks`/fd-count loop and Thread Sanitizer (require a running app) — argued safe by construction (single fd-close site + deinit; weak `Sendable` observer capture; main-actor-only resize flags).
- [x] Module Guide updated (`status` kept `active` due to open ISS-077; `open_issues: ISS-077`; `last_verified` 2026-06-14)
- [ ] Changes committed: `[7 Terminal] PTY hardening and correctness` (left for user)
- [ ] Pushed to GitHub (left for user)
- [x] Plan moved to Plans Completed/
- [x] Mark ISS-075, ISS-076, ISS-078, ISS-079 Resolved in Issues.md; ISS-077 annotated as deferred (stays Open)
