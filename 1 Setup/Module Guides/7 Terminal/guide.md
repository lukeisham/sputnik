---
module: 7 Terminal
status: stable
last_updated: 2026-06-15
last_verified: 2026-06-15
---

## Purpose
Host an interactive Zsh shell inside Sputnik over a pseudo-terminal, rendering its output and forwarding keystrokes, with its working directory bound to the active workspace folder.

## Diagram
```
┌──────────────────────────────────────────────────────────────┐
│  Terminal                                  [Profile: Default ▾]│
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ ~/Developer/App_Sputnik %  git status                    │ │  ← scrollback
│ │ On branch main                                           │ │     buffer
│ │ nothing to commit, working tree clean                    │ │     (ring buffer,
│ │ ~/Developer/App_Sputnik % █                              │ │      capped lines)
│ └──────────────────────────────────────────────────────────┘ │
│  ← pinned to the bottom slot; cannot be relocated (SR per 2.4) │
└──────────────────────────────────────────────────────────────┘

 Keystroke (NSView)                         PTY master fd
       │  KeyEncoder                              ▲
       ▼  (Arrows/Backspace/Ctrl-C → ANSI bytes)  │ write
  ┌─────────────────────┐   stdin            ┌──────────────┐
  │  TerminalSession     │ ───────────────▶ │  Zsh process  │
  │  (actor)             │   stdout/stderr   │ (forkpty;     │
  │                      │ ◀─────────────── │  ctrl-tty)    │
  └─────────┬───────────┘                    └──────────────┘
            │ AsyncStream<Data>  [weak self] listener (SW-2)
            ▼
   TerminalEmulator (parse ANSI/VT)
            │ screen cells + scrollback
            ▼
   TerminalRenderer (NSViewRepresentable, @MainActor)

 WindowState.activeWorkspaceDirectory (per-window, 2.2) changes
            └──▶ session writes `cd <url>\n` to stdin

 AppDelegate.applicationShouldTerminate
            └──▶ AppState.allTerminalManagers  ← collects all windows
                    └──▶ for each: manager.killAllPTYs() [concurrent]
```

## Source Files
| File | Responsibility |
|---|---|
| `TerminalView.swift` | Top-level SwiftUI panel view — composes profile chrome, `TerminalRenderer`, alert/disabled/placeholder states; wires `KeyEncoder` → `TerminalManager`; registers `TerminalManager` on `WindowState` for per-window isolation and clean shutdown; observes `activeWorkspaceDirectory` for `cd` sync |
| `TerminalRenderer.swift` | `NSViewRepresentable` bridging `TerminalTextView` into SwiftUI — forwards `onKeyInput`, `onResize`, snapshot, and profile; empty `Coordinator` placeholder (SW-3) |
| `TerminalTextView.swift` | Raw `NSView` subclass — draws the emulator's cell grid using Core Text; handles `keyDown` → `KeyEncoder`, `mouseDown`/`mouseDragged` for text selection (ISS-059), `viewDidMoveToWindow`/`mouseDown` for first-responder focus (ISS-021), `NSView.frameDidChangeNotification` observer for live resize (ISS-022); owns `RenderThrottle` for debounced snapshot rendering |
| `TerminalSession.swift` | `actor` owning the PTY master fd and the Zsh child pid — `start(workingDirectory:observer:)`, `send(_:)`, `resize(cols:rows:)`, `terminate()`; launches the shell via `PTYSpawn` (forkpty); delivers output as a **bounded** `AsyncStream<Data>` driven by a `PTYChannel`; detects exit via `DispatchSourceProcess`+`waitpid`; `terminate()` escalates SIGTERM → SIGKILL; `deinit` kills/tears down as a leak safety net (SW-2); the `TerminalAIOutputObserving` observer is **handed in at `start()` and captured weakly** in the channel's line callback — no shared mutable observer var (ISS-076) |
| `PTYChannel.swift` | `final class` (`@unchecked Sendable`) bridging the master fd to GCD `DispatchSource` read/write sources — event-driven reads (ISS-068), non-blocking queued writes (ISS-074), EOF detection (ISS-070); all mutable state confined to one private serial queue; the **MR-3 documented exception** to SW-1. Also defines `IncrementalLineDecoder`, a plain value type that decodes the byte stream into observer lines while carrying a partial multi-byte UTF-8 code point and partial line across reads (ISS-079) |
| `TerminalManager.swift` | `@MainActor ObservableObject` — orchestrates session lifecycle, emulator feed, snapshot publishing; conforms to `TerminalLifecycle` (2.6) for clean quit; `syncWorkingDirectory(_:)` for `cd`; `resize(cols:rows:)` for PTY + emulator resize; `send(_:)` for keyboard input |
| `TerminalEmulator.swift` | `actor` — parses raw PTY bytes via `ANSIParser` and applies operations to grid; supports alt-screen buffer, SGR attributes, scrollback, cursor save/restore, title setting; produces `Sendable` `EmulatorSnapshot` for `@MainActor` rendering (SW-1) |
| `KeyEncoder.swift` | Pure enum — translates `TerminalKeyEvent` into ANSI/VT byte sequences; no AppKit imports, trivially testable (spec 7.6) |
| `PTYSpawn.swift` | `enum` namespace — launches Zsh via `forkpty(3)` so the slave becomes the child's **controlling terminal** (job control, Ctrl-C, SIGWINCH — ISS-071); builds argv/env C buffers pre-fork and runs only async-signal-safe calls in the child; returns the master fd + pid; decodes `waitpid` status into an exit code (MR-5; documented departure from MR-4) |
| `ZDOTDIRShim.swift` | `enum` namespace — installs OSC 133 shell-integration hooks via a `ZDOTDIR` shim instead of timed stdin injection (ISS-077). Pure `contents()` generates four shim startup scripts (`.zshenv`/`.zprofile`/`.zshrc`/`.zlogin`) that re-source the user's real dotfiles and append the hooks **after** `.zshrc`; `install()` writes them to a private temp dir (`0700`/`0600`). Shim dir + real `ZDOTDIR` are handed to the child as env vars (`SPUTNIK_SHIM_DIR`, `SPUTNIK_USER_ZDOTDIR`), so the scripts carry no interpolated paths |
| `ScrollbackBuffer.swift` | Fixed-capacity ring buffer of rendered lines — drops oldest on overflow (SR-3); `Sendable` value type |
| `ANSIParser.swift` | Parses raw `Data` into `TerminalOp` values; handles CSI sequences, SGR, OSC title, alt-screen, and printable characters |
| `ScreenCell.swift` | `Sendable` value type for a single terminal cell — `character`, `foreground`/`background` (`CellColor`), `style` (`CellStyle`: bold/italic/underline/inverse etc.) |
| `CellPosition.swift` | `Hashable & Sendable` struct representing a `(row, col)` position in the terminal grid; used by the selection model in `TerminalTextView` |
| `TerminalProfile.swift` | `Sendable & Equatable` value type — font name/size, foreground/background colour, 16-colour ANSI palette, scrollback line limit |
| `Package.swift` | SPM manifest — declares dependencies on `FoundationModule` and `SputnikShared` |
| `Tests/TerminalModuleTests.swift` | Unit tests — covers `KeyEncoder`, `TerminalEmulator`, `ScrollbackBuffer`, `ANSIParser`, and related types; `IncrementalLineDecoderTests` verifies UTF-8-split reassembly and line splitting (ISS-079); `TerminalSessionLifecycleTests` exercises real-PTY EOF teardown (ISS-070) and SIGKILL escalation (ISS-072); `PTYSpawnTests` verifies waitpid-status decoding and that Ctrl-C interrupts a foreground command (controlling terminal, ISS-071) — all under timeouts |

## Wiring Details (verified 2026-06-10)

### Keyboard Focus Path (ISS-021)
Focus is routed to the `TerminalTextView` so `keyDown(with:)` fires and keystrokes reach
`KeyEncoder` → Zsh stdin. The view promotes itself in two places:

1. **`viewDidMoveToWindow()`** — when the view is attached to a window (SwiftUI mounts it),
   calls `window?.makeFirstResponder(self)` so the terminal is immediately interactive
   without requiring a click.
2. **`mouseDown(with:)`** — on click, calls `window?.makeFirstResponder(self)` so clicking
   the panel re-routes focus from another panel back to the terminal.

`acceptsFirstResponder` is `true` and `acceptsFirstMouse(for:)` returns `true`.

### Live Resize Path (ISS-022)
Grid dimensions propagate from the view to both the PTY and the emulator through this
chain:

```
TerminalTextView             (viewDidMoveToWindow registers NSView.frameDidChangeNotification
  │                            observer; reportGridSize() computes cols/rows from bounds ÷
  │  onResize                   cell metrics, de-dupes against lastReportedCols/LastReportedRows)
  ▼
TerminalRenderer              (forwards onResize closure straight through — view owns
  │                             observation, Coordinator is an empty placeholder)
  │  onResize
  ▼
TerminalManager.resize      (stores lastCols/lastRows; coalesces into ONE in-flight
  ├── session.resize(cols:) → PTY TIOCSWINSZ          apply loop that always re-reads the
  └── emulator.resize(cols:) → grid reshape + snapshot  latest size — no unordered detached
                                                        Tasks that could apply a stale size, ISS-078)
```

**Resize coalescing (ISS-078):** a live drag fires many `resize` calls in quick
succession. `TerminalManager` keeps a single `resizeLoop` task; extra calls just set
`resizePending` and update `lastCols`/`lastRows`. The loop drains the pending flag,
re-reading the *latest* dimensions on each pass, so the grid always settles at the final
size even though each apply has `await` suspension points. The flags are mutated only on
the main actor, so there is no race. The loop is cancelled in `stopSession`/`deinit`.

**Session-start seeding:** `TerminalManager.startSession` creates the emulator with a
`80×24` transient default, then after the PTY session is running, re-applies the stored
`lastCols`/`lastRows` (which may have been set by an earlier `onResize` if the view was
already sized). This prevents a race between the first frame-change notification and the
async session launch.

### Profile Chrome
`TerminalView`'s chrome bar displays `"<fontName> <fontSize>"` (e.g. `"Menlo 13"`) read
from the live `TerminalProfile`, which is computed from `@Environment(SettingsStore.self)`
fields. This replaces the misleading hardcoded `"Profile: Default"` label.

## Technical Summary
- **Framework(s):** Darwin POSIX (`forkpty`, `execve`, `waitpid`, `kill`, `ioctl`), GCD `DispatchSource` (read/write/process bridges, MR-3), AppKit via `NSViewRepresentable` (raw rendering per SW-3), SwiftUI, Swift Concurrency. The shell is **no longer** launched via `Foundation.Process` (see MR-4 note below).
- **Key types:**
  - `TerminalSession` (`actor`, `TerminalSession.swift`) — owns the PTY master fd (`Int32`) and the Zsh child pid; exposes `start(workingDirectory:observer:)`, `send(_ bytes: Data)`, `resize(cols:rows:)`, and `terminate()`; launches via `PTYSpawn.spawnLoginShell` (forkpty); serialises lifecycle control through actor isolation while delegating raw fd I/O to a `PTYChannel`; outputs a **bounded** `AsyncStream<Data>` whose continuation is finished on PTY EOF; detects shell exit via `DispatchSourceProcess(.exit)` + `waitpid` (the sole reap site); channel callbacks capture `[weak self]` so the actor deallocates (SW-2). The AI observer is passed in at `start()` and captured **weakly** in the channel's `onLine` closure — there is no `nonisolated(unsafe)` observer property, so nothing is read/written across threads (ISS-076)
  - `PTYChannel` (`final class @unchecked Sendable`, `PTYChannel.swift`) — GCD `DispatchSource` bridge for the master fd; event-driven non-blocking reads replace the old blocking `availableData` loop (ISS-068); writes are queued and drained on writability (ISS-074); reports EOF and split lines via `@Sendable` callbacks; all mutable state confined to one serial queue; closes the master fd from the read source's cancel handler (MR-3 documented `DispatchSource` exception to SW-1). Line splitting goes through an `IncrementalLineDecoder` so a UTF-8 code point split across two reads is reassembled rather than dropped (ISS-079)
  - `IncrementalLineDecoder` (`struct`, `PTYChannel.swift`) — value-type streaming decoder: `feed(_:) -> [String]` returns completed observer lines while holding an incomplete trailing UTF-8 sequence and the partial current line across calls; `flush()` emits a final unterminated line at EOF. No fd or concurrency, so unit-testable in isolation (ISS-079)
  - `TerminalManager` (`@MainActor ObservableObject`, `TerminalManager.swift`) — orchestrates session lifecycle, emulator feed, snapshot publishing; conforms to `TerminalLifecycle` (2.6); wires `TerminalAIOutputObserving` to sessions; `syncWorkingDirectory(_:)` for `cd`; `resize(cols:rows:)` for PTY + emulator resize; `sessionEndedMessage: String?` is set when the pump stream finishes or a PTY write fails, and cleared at the start of `startSession` — `TerminalContent` observes it to show the dead-session banner (ISS-110); logs via `SputnikLogger.terminal` (ISS-109)
  - `TerminalView` (`View`, `TerminalView.swift`) — top-level SwiftUI panel; composes profile chrome, `TerminalRenderer` (via `TerminalContent`), alert/disabled/placeholder states; registers manager on `WindowState.terminalManager` for per-window isolation
  - `TerminalContent` (private `View`, `TerminalView.swift`) — `@ObservedObject`-wraps `TerminalManager` so `@Published` changes (snapshot, sessionEndedMessage) drive re-renders without the outer `TerminalView` needing to observe the manager directly; owns the `TerminalRenderer` + dead-session banner overlay; intercepts Return in `onKeyInput` to restart the session when `sessionEndedMessage != nil` (ISS-110)
  - `TerminalTextView` (`NSView`, `TerminalTextView.swift`) — draws the emulator's cell grid via Core Text; handles keyboard input (`keyDown` → `KeyEncoder`), text selection (ISS-059), first-responder focus (ISS-021), and live resize (ISS-022)
  - `TerminalRenderer` (`NSViewRepresentable`, `TerminalRenderer.swift`) — SwiftUI bridge to `TerminalTextView` (SW-3)
  - `TerminalEmulator` (`actor`, `TerminalEmulator.swift`) — parses raw ANSI/VT byte stream via `ANSIParser` into a grid of `ScreenCell`s plus capped scrollback; supports alt-screen buffer, SGR attributes, cursor save/restore, title setting; produces `Sendable` `EmulatorSnapshot` for `@MainActor` rendering
  - `ANSIParser` (`TerminalOp` parser, `ANSIParser.swift`) — parses raw `Data` into `TerminalOp` values; handles CSI sequences, SGR, OSC title, alt-screen, and printable characters
  - `KeyEncoder` (`enum`, `KeyEncoder.swift`) — translates `TerminalKeyEvent` into ANSI/VT byte sequences; no AppKit imports (spec 7.6)
  - `PTYSpawn` (`enum`, `PTYSpawn.swift`) — launches Zsh via `forkpty(3)`, giving the child a controlling terminal (ISS-071); returns the master fd + pid; `exitCode(fromWaitStatus:)` decodes `waitpid` status (MR-5; documented departure from MR-4)
  - `ZDOTDIRShim` (`enum`, `ZDOTDIRShim.swift`) — generates and installs the `ZDOTDIR` shim that carries the OSC 133 shell-integration hooks (ISS-077). `contents()` is pure (unit-testable); `install()` writes the four shim files to a private temp dir. `TerminalSession.buildEnvironment` calls `install()`, owns the returned directory, and removes it on teardown (`cleanupPTY`/`deinit`); on install failure it logs via `SputnikLogger.terminal` and launches **without** integration (SR-2) — never the old timed stdin injection
  - `ScrollbackBuffer` (`Sendable` ring buffer, `ScrollbackBuffer.swift`) — fixed-capacity ring buffer of rendered lines; drops oldest on overflow (SR-3)
  - `ScreenCell` (`Sendable`, `ScreenCell.swift`) — single cell model: `character`, `foreground`/`background` (`CellColor`), `style` (`CellStyle`)
  - `CellPosition` (`Hashable & Sendable`, `CellPosition.swift`) — `(row, col)` position in the terminal grid; used by `TerminalTextView` selection model
  - `TerminalProfile` (`Sendable & Equatable`, `TerminalProfile.swift`) — font name/size, foreground/background colour, 16-colour ANSI palette, scrollback line limit; sourced from Settings (2.3)
  - `EmulatorSnapshot` (`Sendable`, `TerminalEmulator.swift`) — immutable snapshot of terminal grid + scrollback + cursor state, handed from emulator actor to `@MainActor` renderer
  - `TerminalKeyEvent` / `TerminalModifiers` — platform-independent key event types consumed by `KeyEncoder`
- **Per-window terminal:** Each window gets its own `TerminalManager`, stored on `WindowState.terminalManager`. `TerminalView` reads `windowState.activeWorkspaceDirectory` (not `AppState`) for the `cd` sync, and registers itself via `windowState.terminalManager = manager` on appear. This ensures each window's shell runs in its own project directory with no terminal state leaking between windows.
- **Threading model:** PTY reads are **event-driven** — a `DispatchSource` read source in `PTYChannel` reads available bytes non-blockingly on a private serial queue and yields them into the bounded `AsyncStream<Data>`; no thread is parked for the session's lifetime (replaces the old blocking `availableData` task, ISS-068). Writes are queued on the same serial channel queue and drained on `EAGAIN` via a write source, so the actor never blocks on a full PTY buffer (ISS-074). The channel's callbacks capture `[weak self]`, so nothing holds the `TerminalSession` actor alive for the I/O lifetime (SW-2). ANSI parsing runs off the main thread inside the emulator (`TerminalEmulator` is an actor); only the final cell-grid hand-off and all `NSView` drawing occur on `@MainActor`. The manager's pump `Task` re-resolves `[weak self]` each loop iteration so it never strong-holds the manager (ISS-069). `cd` synchronisation observes `WindowState.activeWorkspaceDirectory` (2.2) on the main actor and writes to the PTY through the session actor.
- **Data flow:** `TerminalSession.start()` launches Zsh via `PTYSpawn` (forkpty), which opens the PTY and makes the slave the child's controlling terminal; the parent keeps only the master fd, so the master sees a true EOF when Zsh exits (ISS-070, ISS-071) → Zsh output arrives on the master fd via the `PTYChannel` read source → bounded `AsyncStream<Data>` → `TerminalEmulator` parses bytes into cells + scrollback → `TerminalRenderer` draws on `@MainActor`. Inbound: keystroke → `KeyEncoder` → `TerminalManager.send(_:)` → `TerminalSession.send(_:)` → PTY master write → Zsh stdin. Directory: `windowState.activeWorkspaceDirectory` change → `TerminalManager.syncWorkingDirectory(_:)` → session writes `cd <url>`.
- **Clean shutdown:** `AppDelegate.applicationShouldTerminate` collects all `TerminalManager` instances via `AppState.allTerminalManagers` (a computed property that iterates all `WindowState.terminalManager` references). Each manager's `killAllPTYs()` is called concurrently in a `TaskGroup`. Only when all PTYs have exited does `NSApp.replyToApplicationShouldTerminate(true)` fire.
- **State owned:** the PTY master fd, the Zsh child pid + its exit `DispatchSource`, the emulator screen grid, the `ScrollbackBuffer`, the cursor position, the active `TerminalProfile`, and the selection model (`selectionStart`/`selectionEnd` cell positions). Owns no file content and does not write `AppState` (read-only consumer of the window's workspace directory).
- **Text selection (ISS-059):** `TerminalTextView` tracks a drag-based selection via `mouseDown`/`mouseDragged` overrides. Selected cells are highlighted with `NSColor.selectedTextBackgroundColor` at 40% alpha. `⌘C` copies selected cells (row-joined with `\n`) to `NSPasteboard.general`. `⌘V` reads plain text from the pasteboard and forwards it as UTF-8 data to `onKeyInput`. Selection is cleared on new snapshot output and when the user presses Escape.
- **Dependencies:** Foundation 2.2 Global State (`WindowState` for per-window workspace directory + terminal manager registration); 2.3 Settings (`TerminalProfile`: font, colours, scrollback cap); 2.4 UI/UX (panel chrome, pinned-bottom slot, error dialogs); 2.6 App Lifecycle (terminate sessions on app quit via `AppState.allTerminalManagers`); `SputnikShared` (`RenderThrottle` used by `TerminalTextView`). The terminal never calls another panel directly.
- **Failure modes:**
  - PTY open / `forkpty` fails → `PTYSpawn` throws `SputnikError.processLaunchFailed`; surface via 2.4 error dialog; panel shows a disabled placeholder; no crash, no force-unwrap (SR-2).
  - Zsh fails to `execve` (missing binary, sandbox denial) → the child `_exit(127)`s; the exit source reports a non-zero code and the session settles to `.exited`; the panel goes idle and offers retry.
  - **Zombie processes** (spec 7.5) → `PTY Lifecycle Management`: `terminate()` sends `SIGTERM` (via `kill(pid,…)`), polls the actor's `hasExited` flag for up to ~2 s, and **escalates to `SIGKILL`** if the shell is still alive (a shell trapping SIGTERM cannot survive — ISS-072). Reaping happens exactly once, in the exit source's `waitpid`. The session is terminated on tab close and on app quit (driven by 2.6 App Lifecycle), so no orphaned shell survives.
  - Scrollback growth → ring buffer caps line count from the active profile; oldest lines are released (SR-3). The raw output queue is also bounded: `outputStream` uses `.bufferingNewest` so a fast producer (e.g. `cat` of a huge file) cannot grow `Data` without limit (ISS-073) — under flood the oldest chunks drop while the most recent screen state is preserved.
  - Master fd read returns EOF / Zsh exits → the `PTYChannel` read source detects EOF (read returns 0, or `EIO` once the slave is gone), finishes the `AsyncStream`, and the session settles to `.exited`; the channel cancels its sources and closes the fd from the read source's cancel handler — no use-after-close race (ISS-070). The manager shows the dead state via `isRunning = false`.
  - PTY write fails (slave closed) → discard the keystroke, log a warning via `SputnikLogger.terminal`, set `sessionEndedMessage` to prompt restart, mark `isRunning = false`. Writes are non-blocking (queued in `PTYChannel`), so a full input buffer (Ctrl-S, large paste) never wedges the actor (ISS-074, ISS-110).
  - Shell-integration install fails (temp-dir/file write error) → `ZDOTDIRShim.install()` throws; `buildEnvironment` logs via `SputnikLogger.terminal` and launches the shell with no `ZDOTDIR`/`SPUTNIK_*` env, i.e. **without** OSC 133 hooks. A machine-level `/etc/zshenv` that hard-sets `ZDOTDIR` runs before our shim's `.zshenv` and would also defeat it — rare and out of scope; the terminal still works, only shell integration is absent (SR-2).
  - Shell exits (pump stream finishes) → `TerminalManager` sets `isRunning = false` and `sessionEndedMessage = "Session ended — press ↵ to restart"`; `TerminalContent` overlays the grid with a translucent banner; pressing Return in the dead terminal (intercepted in `onKeyInput`) or clicking the "Restart" button calls `startSession` (ISS-110).

## Invariants
- `TerminalSession` is an **actor** — lifecycle control (`start`/`send`/`resize`/`terminate`) is serialised through actor isolation; raw fd I/O is delegated to `PTYChannel` (SW-1)
- `PTYChannel` confines **all** its mutable state to a single private serial `DispatchQueue` — it is the only `DispatchSource` bridge in the module, documented at the call site as the MR-3 exception to SW-1
- The AI output observer is **never** held in shared mutable state — it is handed to `TerminalSession.start()` and captured **weakly** in the channel's line callback; `TerminalAIOutputObserving` is `Sendable` so the capture is race-free without `nonisolated(unsafe)` (ISS-076, SW-1)
- Observer line splitting is **incremental** — `IncrementalLineDecoder` carries a partial multi-byte UTF-8 code point and partial line across reads, so output split on an arbitrary byte boundary never drops characters or whole lines (ISS-079)
- `TerminalManager.resize` is **coalesced** — at most one apply loop runs at a time and it always applies the latest `lastCols`/`lastRows`, so rapid live-resize can never leave the PTY/emulator grid at a stale size (ISS-078, SR-4)
- The PTY output is event-driven, not a blocking reader thread — no cooperative-pool thread is parked for a session's lifetime (ISS-068); the `PTYChannel` and manager pump callbacks capture `[weak self]` and re-resolve it per turn, so neither the `TerminalSession` actor nor the `TerminalManager` is held alive by I/O (SW-2, ISS-069 — canonical PTY infinite-loop leak risk)
- The shell is launched via **`forkpty`** so the slave is its **controlling terminal** — job control, Ctrl-C (SIGINT), and SIGWINCH reach the foreground process group (ISS-071). The parent holds only the master fd, so shell exit is a natural EOF and the master fd is closed exactly once, from the `PTYChannel` read source's cancel handler — never leaked even if `terminate()` is missed (`deinit` tears the channel down), and there is no app-level non-reentrant `ptsname` call because `forkpty` opens the slave inside libc (ISS-070, ISS-075)
- The shell is **not** launched via `Foundation.Process` — the documented departure from MR-4 (a controlling terminal cannot be set through `Process`). Between `forkpty` and `execve` the child calls only async-signal-safe functions
- Shell integration (OSC 133) is installed via a **`ZDOTDIR` shim**, never by writing a snippet to stdin after a timed delay (ISS-077). The shim re-sources the user's real `.zshenv`/`.zprofile`/`.zshrc`/`.zlogin` in order and appends the hooks **after** `.zshrc`, so a wholesale `precmd_functions=(...)` reset in the user's config cannot drop them and no snippet text echoes into the first prompt. The shim restores the real `ZDOTDIR` before sourcing each real file and re-captures any user relocation of `ZDOTDIR`. The shim temp dir is owned by `TerminalSession` and removed on teardown
- The `outputStream` is **bounded** (`.bufferingNewest`) — raw output `Data` can never grow without limit (ISS-073)
- `terminate()` **escalates SIGTERM → SIGKILL** with an exit check, so no shell can outlive teardown (spec 7.5, ISS-072); it is idempotent
- Shell exit is detected and reaped in **exactly one place** — the `DispatchSourceProcess(.exit)` handler's `waitpid`; `terminate()` only signals and polls `hasExited`, so there is no double-reap (MR-5, SR-2)
- `TerminalEmulator` is an **actor** — all ANSI parsing and grid mutation run off the main thread; only `EmulatorSnapshot` (a `Sendable` value) crosses the actor boundary (SW-1, SR-4)
- `TerminalManager` is `@MainActor` — all observable state (`snapshot`, `isRunning`, `pendingAlert`) is published from the main actor
- The terminal is a **read-only consumer** of `AppState` and `WindowState` — it never writes `activeWorkspaceDirectory`, never mutates `AppState.openDocuments` (SR-1)
- `ScrollbackBuffer` is a fixed-capacity ring buffer — its capacity comes from `TerminalProfile.scrollbackLineLimit` and it can never grow unbounded (SR-3)
- `TerminalTextView` uses `RenderThrottle` to debounce snapshot-driven redraws — prevents excessive Core Text rendering during rapid output (SR-4)

## Spec Reference
> Extracted verbatim from `readme.md`:

```
7. TERMINAL = the area where users can interact with the shell and run commands for the folder being viewed in the FILE EXPLORER.
  1. Shell hosting and integration in order to host Zsh on macOS
  2. Text Rendering and Terminal Emulation
  3. The Scrollback Buffer
  4. Customization and Profiles
  5. PTY Lifecycle Management (cleaning up or killing background Zsh shell processes when a terminal tab or the app closes to avoid zombie processes).
  6. Keyboard Input Encoding (translating Special Keys like Arrow Keys, Backspace, Delete, and Ctrl+C into proper ANSI byte streams that Zsh understands).
```
