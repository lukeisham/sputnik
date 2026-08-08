---
plan: Implement Terminal module source
module: 7 Terminal
created: 2026-06-08
status: pending
related_issues: ISS-002, ISS-003
---

## Purpose
Write the Swift source for the Terminal module (7) — a PTY-hosted interactive Zsh shell with ANSI/VT emulation, a capped scrollback buffer, special-key encoding, profile-driven customisation, and clean PTY lifecycle — so Sputnik's bottom-pinned terminal panel can run shell commands against the active workspace folder.

> **Scope note (per user decision):** This plan only *authors `.swift` files* into the existing `7 Terminal/` folder. It does **not** create an Xcode project, target, entitlements, or build system — you will do that in Xcode later. No compile step is in scope; every file is written Swift-6-strict-concurrency-clean *by inspection*.

> **Depends on Foundation (skill Rule — module-2 flag):** Terminal consumes Foundation contracts that the *"Implement Foundation module source"* plan authors but which are **not yet committed**: `AppState` (2.2, active directory), the `TerminalLifecycle` protocol (2.6), `SputnikAlert` (2.4), and the `SputnikError` / `TerminalProfile`-from-Settings seams (see ISS-002, ISS-003). This plan must be executed **after** the Foundation plan, or those references will dangle. Terminal calls Foundation only through protocols/shared types — it never calls another panel directly (SR-1).

## Success Condition
All true by inspection (no build in scope):

1. Every "Key type" named in the 7 Terminal guide exists as a Swift file in `7 Terminal/`, one responsibility per file (**SR-6**) — the ANSI parser, screen-cell model, scrollback ring, PTY handle, session actor, key encoder, renderer, and panel view are each their own file.
2. **MR-5**: PTY is opened via the `posix_openpt → grantpt → unlockpt → ptsname` sequence in `PTYHandle`; failure throws rather than force-unwraps.
3. **MR-4**: the Zsh `Process` binds `standardInput/Output/Error` to the PTY **slave `FileHandle`**, never a `Pipe`.
4. **SW-2 (canonical leak)**: the long-lived PTY-output listener `Task(priority: .utility)` captures `[weak self]` so `TerminalSession` deallocates.
5. **SW-1**: PTY I/O is serialised through an `actor`; shell output is an `AsyncStream<Data>`; no `DispatchQueue` for business logic, no completion handlers. Snapshots crossing to `@MainActor` are `Sendable`.
6. **SW-3**: AppKit (`NSViewRepresentable` + `NSView`) appears **only** in the renderer, with a doc-comment justifying it by ANSI rendering throughput; everything else is SwiftUI/Foundation.
7. **SR-3**: `ScrollbackBuffer` is a fixed-capacity ring buffer that drops the oldest line on overflow — scrollback can never grow unbounded.
8. **PTY lifecycle (spec 7.5)**: `terminate()` sends `SIGTERM`, waits, closes the master fd, and nils the `Process`; `TerminalManager` conforms to Foundation's `TerminalLifecycle` so 2.6 App Lifecycle kills all sessions on quit — no zombie shells.
9. **SR-2**: no force-unwraps; every failure mode in the guide (PTY open fail, Zsh launch fail, EOF/shell exit, PTY write fail) is handled explicitly and surfaced via `SputnikAlert`/inline notice.
10. Every type/method carries `///` doc-comments (**SW-4**).

## Steps

- [ ] 1. **Author the value types — `TerminalProfile`, `ScreenCell`**
   What: `7 Terminal/TerminalProfile.swift` — a `Sendable` value type (font name+size, foreground/background/ANSI palette colours, `scrollbackLineLimit: Int`) with hardcoded defaults. `7 Terminal/ScreenCell.swift` — a `Sendable` value type for one rendered cell (character + colour/style attributes).
   Why: These are the leaf types every later file references; defining them first means the emulator, renderer, and buffer compile against real types. Per ISS-002 the profile carries its own defaults now and reads from Settings (2.3) only once 2.3 exposes the fields — documented at the type so the seam is explicit, not silently broken.

- [ ] 2. **Author `ScrollbackBuffer`**
   What: `7 Terminal/ScrollbackBuffer.swift` — a fixed-capacity ring buffer of rendered lines (`[ScreenCell]` per line); appending past capacity drops the oldest line. Capacity comes from `TerminalProfile.scrollbackLineLimit`.
   Why: Spec 7.3 + SR-3 — caps terminal RAM regardless of output volume. Isolating it (SR-6) keeps the emulator focused on parsing/grid state.

- [ ] 3. **Author `PTYHandle`**
   What: `7 Terminal/PTYHandle.swift` — wraps `posix_openpt → grantpt → unlockpt → ptsname` (Darwin POSIX), returning the master `FileHandle` and the slave path. Each POSIX call's failure is checked and converted to a thrown `SputnikError.hardwareAccessDenied` (no `!`). Provides `close()` for the master fd.
   Why: MR-5 — single home for the PTY-open sequence (SR-6, one responsibility). Throwing on failure (not force-unwrapping the fd) satisfies SR-2 and the guide's first failure mode.

- [ ] 4. **Author `KeyEncoder`**
   What: `7 Terminal/KeyEncoder.swift` — pure function/type translating special keys (arrows, Backspace, Delete, Ctrl-C, Home/End, etc.) into the ANSI byte sequences (`Data`) Zsh expects.
   Why: Spec 7.6 — keystrokes must reach Zsh as proper ANSI bytes. Pure and AppKit-free so it is trivially testable and reusable (SR-6).

- [ ] 5. **Author `ANSIParser`**
   What: `7 Terminal/ANSIParser.swift` — consumes the raw byte stream and emits parsed terminal operations (print glyph, move cursor, set attribute, erase, newline, etc.). Holds only incremental parse state; no AppKit, no grid.
   Why: Splitting the byte→operation parser from the grid model (next step) honours SR-6 (sequential pipeline, but distinct concerns) and keeps the parser unit-testable in isolation.

- [ ] 6. **Author `TerminalEmulator`**
   What: `7 Terminal/TerminalEmulator.swift` — an `actor` that feeds incoming `Data` through `ANSIParser`, applies the resulting operations to a screen-cell grid + cursor, and pushes scrolled-off lines into `ScrollbackBuffer`. Exposes an immutable, `Sendable` grid+scrollback snapshot for the renderer.
   Why: Guide threading model — ANSI parsing runs off the main thread; making the emulator an `actor` keeps that work isolated (SW-1) and produces a `Sendable` snapshot safe to hand to `@MainActor` (SR-4).

- [ ] 7. **Author `TerminalSession`**
   What: `7 Terminal/TerminalSession.swift` — an `actor` owning the PTY master `FileHandle` (via `PTYHandle`) and the Zsh `Foundation.Process`. `start()` opens the PTY and launches Zsh with `executableURL`, environment, working directory, and `standardInput/Output/Error` bound to the **slave `FileHandle`** (MR-4 — never a `Pipe`). Exposes `send(_ bytes: Data)`, `resize(cols:rows:)`, `terminate()`, and an `AsyncStream<Data>` of shell output read from the master fd. The output-reading `Task(priority: .utility)` captures `[weak self]`. `terminate()` sends `SIGTERM`, waits, closes the master fd, nils the `Process`.
   Why: Spec 7.1 + 7.5; MR-4/MR-5; SW-1 (actor + AsyncStream); SW-2 (the `[weak self]` listener is the guide's named infinite-loop leak risk). Explicit EOF/launch-failure/write-failure handling satisfies SR-2 and the guide failure modes.

- [ ] 8. **Author `TerminalManager`**
   What: `7 Terminal/TerminalManager.swift` — a `@MainActor` coordinator that creates/owns `TerminalSession`(s) + their `TerminalEmulator`, observes `AppState.activeWorkspaceDirectory` (2.2) and writes `cd <url>\n` to the session on change, and **conforms to Foundation's `TerminalLifecycle` protocol** implementing `killAllPTYs() async` (calls `terminate()` on every session). Pumps each session's `AsyncStream<Data>` into its emulator.
   Why: This is the seam to 2.6 App Lifecycle (kills sessions on quit → no zombies, spec 7.5) and to 2.2 (directory sync). Keeping coordination here — not in the SwiftUI view — keeps the view thin and respects SR-1 (Terminal reads `AppState`, never writes it).

- [ ] 9. **Author `TerminalTextView` (NSView)**
   What: `7 Terminal/TerminalTextView.swift` — an `NSView` subclass that draws the emulator's `Sendable` cell-grid snapshot (glyphs, colours, cursor) and routes `keyDown`/key events out to a callback (consumed by `KeyEncoder` → session). All drawing on `@MainActor`.
   Why: SW-3 — raw AppKit drawing is justified by ANSI rendering throughput; isolating the `NSView` from its SwiftUI wrapper (next step) respects SR-6.

- [ ] 10. **Author `TerminalRenderer` (NSViewRepresentable)**
   What: `7 Terminal/TerminalRenderer.swift` — an `NSViewRepresentable` (`@MainActor`) wrapping `TerminalTextView`; `updateNSView` pushes the latest grid snapshot; a doc-comment states the SW-3 justification (ANSI throughput) at the call site.
   Why: SW-3 requires the AppKit drop-down to be the minimal, documented bridge; this file is that bridge and nothing more (SR-6).

- [ ] 11. **Author `TerminalView` (SwiftUI panel)**
   What: `7 Terminal/TerminalView.swift` — the SwiftUI panel view: hosts `TerminalRenderer`, shows the profile chrome (`[Profile: Default ▾]`), reads `TerminalProfile` (defaulting locally per ISS-002, observing Settings 2.3 when available), owns the `TerminalManager`, wires key events through `KeyEncoder` to the session, and renders the disabled/placeholder state on PTY/launch failure via `SputnikAlert`. Bottom-pinned slot is enforced by 2.4 (not here).
   Why: Spec 7.1–7.4 surface; this is the module's public SwiftUI entry point the 2.4 layout drops into the pinned bottom slot. Building it last means every dependency it composes already exists.

- [ ] 12. **Cross-file consistency + rules audit**
   What: Re-read all 7-module files together. Verify SR-6 split; MR-4 (slave `FileHandle`, no `Pipe`) and MR-5 (full POSIX sequence) present; `[weak self]` on the listener Task (SW-2); actors + `AsyncStream`, `Sendable` snapshots (SW-1); AppKit confined to renderer with justification (SW-3); ring buffer caps RAM (SR-3); `terminate()` SIGTERM→close→nil and `TerminalLifecycle` conformance (spec 7.5); zero `!` (SR-2); `///` on every type (SW-4). Confirm every Foundation reference (`AppState`, `TerminalLifecycle`, `SputnikAlert`, `SputnikError`) matches the names the Foundation plan defines; fix drift or note it against ISS-002/ISS-003.
   Why: With no compiler in scope, this whole-set read is the only check that the files cohere and that the Foundation seam names line up.

## Risks and Constraints
- **Hard dependency on the Foundation plan.** `AppState`, `TerminalLifecycle`, `SputnikAlert`, and the `SputnikError`/`TerminalProfile`-from-Settings seams are authored by the Foundation plan and are **not yet committed**. Execute Foundation first; until then these references are forward declarations. (There is no build target either way, per user scope.)
- **ISS-002 / ISS-003 are upstream of full correctness.** This plan works around them — `TerminalProfile` ships local defaults, and `SputnikError` is treated as a Foundation-owned contract Terminal only *references* (defining it in module 7 would violate SR-1). Both issues should be resolved in Foundation, not here.
- **SW-2 leak is the highest-risk item.** The PTY-output listener is a long-lived/near-infinite Task; a strong `self` capture permanently leaks the session and its scrollback. `[weak self]` is mandatory and explicitly audited in Step 12.
- **MR-4 is easy to get wrong.** Binding the `Process` to a `Pipe` instead of the PTY slave `FileHandle` silently breaks interactive programs (vim, pagers). The guide and MR-4 forbid it.
- **No entitlements/sandbox work in scope.** Spawning Zsh and opening a PTY may need specific entitlements when you build the target in Xcode — out of scope here; the code assumes it can launch `Process` and `posix_openpt`.
- **Terminal is a read-only consumer of `AppState`** — it must never write workspace state (SR-1); it only writes `cd` to its own PTY.

## Files Affected
- `7 Terminal/TerminalProfile.swift` — `Sendable` customisation value type (font, colours, scrollback cap) with local defaults
- `7 Terminal/ScreenCell.swift` — `Sendable` single-cell value type (char + attributes)
- `7 Terminal/ScrollbackBuffer.swift` — fixed-capacity ring buffer of rendered lines (SR-3)
- `7 Terminal/PTYHandle.swift` — `posix_openpt → grantpt → unlockpt → ptsname` wrapper (MR-5), throws on failure
- `7 Terminal/KeyEncoder.swift` — special keys → ANSI byte sequences (spec 7.6)
- `7 Terminal/ANSIParser.swift` — raw bytes → parsed terminal operations
- `7 Terminal/TerminalEmulator.swift` — `actor`: applies ops to cell grid + scrollback; emits `Sendable` snapshot
- `7 Terminal/TerminalSession.swift` — `actor`: owns PTY master `FileHandle` + Zsh `Process`; `AsyncStream<Data>` output (MR-4, SW-1, SW-2)
- `7 Terminal/TerminalManager.swift` — `@MainActor` coordinator; conforms to `TerminalLifecycle` (2.6); `cd` sync from `AppState` (2.2)
- `7 Terminal/TerminalTextView.swift` — `NSView` drawing the cell grid (SW-3)
- `7 Terminal/TerminalRenderer.swift` — `NSViewRepresentable` wrapper for the text view (SW-3, documented)
- `7 Terminal/TerminalView.swift` — SwiftUI panel: renderer + profile chrome + failure/placeholder state
- `1 Setup/References/Issues.md` — ISS-002 / ISS-003 status update at closeout (resolved here only if addressed; otherwise left Open for Foundation)
- `1 Setup/Module Guides/7 Terminal/guide.md` — `status` → active + `last_updated` (closeout)

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (Step 12 inspection pass — all 10 points confirmed)
- [ ] ISS-002 / ISS-003 reviewed — resolved in Foundation or left Open with a note (do not silently close)
- [ ] Module Guide 7 Terminal updated (`status` + `last_updated`)
- [ ] Changes committed: `[7 Terminal] Implement Terminal module source`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
