---
module: 7 Terminal
status: stable
last_updated: 2026-06-12
last_verified: 2026-06-12
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
  │  (actor)             │   stdout/stderr   │ (Foundation   │
  │                      │ ◀─────────────── │  Process)     │
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
| `TerminalSession.swift` | `actor` owning the PTY master `FileHandle` and Zsh `Process` — `start()`, `send(_:)`, `resize(cols:rows:)`, `terminate()`; delivers shell output as `AsyncStream<Data>` with `[weak self]` reader task (SW-2); forwards lines to `TerminalAIOutputObserving` observer |
| `TerminalManager.swift` | `@MainActor ObservableObject` — orchestrates session lifecycle, emulator feed, snapshot publishing; conforms to `TerminalLifecycle` (2.6) for clean quit; `syncWorkingDirectory(_:)` for `cd`; `resize(cols:rows:)` for PTY + emulator resize; `send(_:)` for keyboard input |
| `TerminalEmulator.swift` | `actor` — parses raw PTY bytes via `ANSIParser` and applies operations to grid; supports alt-screen buffer, SGR attributes, scrollback, cursor save/restore, title setting; produces `Sendable` `EmulatorSnapshot` for `@MainActor` rendering (SW-1) |
| `KeyEncoder.swift` | Pure enum — translates `TerminalKeyEvent` into ANSI/VT byte sequences; no AppKit imports, trivially testable (spec 7.6) |
| `PTYHandle.swift` | Wraps `posix_openpt → grantpt → unlockpt → ptsname` sequence; returns master `FileHandle` and slave path; all POSIX calls checked, throws `SputnikError.hardwareAccessDenied` on failure (MR-5, SR-2) |
| `ScrollbackBuffer.swift` | Fixed-capacity ring buffer of rendered lines — drops oldest on overflow (SR-3); `Sendable` value type |
| `ANSIParser.swift` | Parses raw `Data` into `TerminalOp` values; handles CSI sequences, SGR, OSC title, alt-screen, and printable characters |
| `ScreenCell.swift` | `Sendable` value type for a single terminal cell — `character`, `foreground`/`background` (`CellColor`), `style` (`CellStyle`: bold/italic/underline/inverse etc.) |
| `CellPosition.swift` | `Hashable & Sendable` struct representing a `(row, col)` position in the terminal grid; used by the selection model in `TerminalTextView` |
| `TerminalProfile.swift` | `Sendable & Equatable` value type — font name/size, foreground/background colour, 16-colour ANSI palette, scrollback line limit |
| `Package.swift` | SPM manifest — declares dependencies on `FoundationModule` and `SputnikShared` |
| `Tests/TerminalModuleTests.swift` | Unit tests — covers `KeyEncoder`, `TerminalEmulator`, `ScrollbackBuffer`, `ANSIParser`, and related types |

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
TerminalManager.resize      (stores lastCols/lastRows; kicks Task to do both:
  ├── session.resize(cols:) → PTY TIOCSWINSZ
  └── emulator.resize(cols:) → grid reshape + snapshot refresh)
```

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
- **Framework(s):** Foundation (`Process`, `FileHandle`), Darwin POSIX (`posix_openpt`, `grantpt`, `unlockpt`, `ptsname`), AppKit via `NSViewRepresentable` (raw rendering per SW-3), SwiftUI, Swift Concurrency
- **Key types:**
  - `TerminalSession` (`actor`, `TerminalSession.swift`) — owns the PTY master `FileHandle` and the Zsh `Process`; exposes `start()`, `send(_ bytes: Data)`, `resize(cols:rows:)`, and `terminate()`; serialises all PTY I/O through actor isolation; outputs `AsyncStream<Data>` with `[weak self]` reader task (SW-2)
  - `TerminalManager` (`@MainActor ObservableObject`, `TerminalManager.swift`) — orchestrates session lifecycle, emulator feed, snapshot publishing; conforms to `TerminalLifecycle` (2.6); wires `TerminalAIOutputObserving` to sessions; `syncWorkingDirectory(_:)` for `cd`; `resize(cols:rows:)` for PTY + emulator resize
  - `TerminalView` (`View`, `TerminalView.swift`) — top-level SwiftUI panel; composes profile chrome, `TerminalRenderer`, alert/disabled/placeholder states; registers manager on `WindowState.terminalManager` for per-window isolation
  - `TerminalTextView` (`NSView`, `TerminalTextView.swift`) — draws the emulator's cell grid via Core Text; handles keyboard input (`keyDown` → `KeyEncoder`), text selection (ISS-059), first-responder focus (ISS-021), and live resize (ISS-022)
  - `TerminalRenderer` (`NSViewRepresentable`, `TerminalRenderer.swift`) — SwiftUI bridge to `TerminalTextView` (SW-3)
  - `TerminalEmulator` (`actor`, `TerminalEmulator.swift`) — parses raw ANSI/VT byte stream via `ANSIParser` into a grid of `ScreenCell`s plus capped scrollback; supports alt-screen buffer, SGR attributes, cursor save/restore, title setting; produces `Sendable` `EmulatorSnapshot` for `@MainActor` rendering
  - `ANSIParser` (`TerminalOp` parser, `ANSIParser.swift`) — parses raw `Data` into `TerminalOp` values; handles CSI sequences, SGR, OSC title, alt-screen, and printable characters
  - `KeyEncoder` (`enum`, `KeyEncoder.swift`) — translates `TerminalKeyEvent` into ANSI/VT byte sequences; no AppKit imports (spec 7.6)
  - `PTYHandle` (`PTYHandle.swift`) — wraps `posix_openpt → grantpt → unlockpt → ptsname`; returns master `FileHandle` and slave path; throws `SputnikError.hardwareAccessDenied` on failure (MR-5, SR-2)
  - `ScrollbackBuffer` (`Sendable` ring buffer, `ScrollbackBuffer.swift`) — fixed-capacity ring buffer of rendered lines; drops oldest on overflow (SR-3)
  - `ScreenCell` (`Sendable`, `ScreenCell.swift`) — single cell model: `character`, `foreground`/`background` (`CellColor`), `style` (`CellStyle`)
  - `CellPosition` (`Hashable & Sendable`, `CellPosition.swift`) — `(row, col)` position in the terminal grid; used by `TerminalTextView` selection model
  - `TerminalProfile` (`Sendable & Equatable`, `TerminalProfile.swift`) — font name/size, foreground/background colour, 16-colour ANSI palette, scrollback line limit; sourced from Settings (2.3)
  - `EmulatorSnapshot` (`Sendable`, `TerminalEmulator.swift`) — immutable snapshot of terminal grid + scrollback + cursor state, handed from emulator actor to `@MainActor` renderer
  - `TerminalKeyEvent` / `TerminalModifiers` — platform-independent key event types consumed by `KeyEncoder`
- **Per-window terminal:** Each window gets its own `TerminalManager`, stored on `WindowState.terminalManager`. `TerminalView` reads `windowState.activeWorkspaceDirectory` (not `AppState`) for the `cd` sync, and registers itself via `windowState.terminalManager = manager` on appear. This ensures each window's shell runs in its own project directory with no terminal state leaking between windows.
- **Threading model:** PTY reads are consumed as an `AsyncStream<Data>` on a long-lived `Task(priority: .utility)` captured with `[weak self]` so the session deallocates (SW-2 — this is the canonical infinite-loop leak risk). ANSI parsing runs off the main thread inside the emulator (`TerminalEmulator` is an actor); only the final cell-grid hand-off and all `NSView` drawing occur on `@MainActor`. `cd` synchronisation observes `WindowState.activeWorkspaceDirectory` (2.2) on the main actor and writes to the PTY through the session actor.
- **Data flow:** `TerminalSession.start()` opens the PTY (`PTYHandle`), launches Zsh via `Process` with `standardInput/Output/Error` bound to the PTY slave `FileHandle` (MR-4 — never a `Pipe`) → Zsh output arrives on the master fd as `AsyncStream<Data>` → `TerminalEmulator` parses bytes into cells + scrollback → `TerminalRenderer` draws on `@MainActor`. Inbound: keystroke → `KeyEncoder` → `TerminalManager.send(_:)` → `TerminalSession.send(_:)` → PTY master write → Zsh stdin. Directory: `windowState.activeWorkspaceDirectory` change → `TerminalManager.syncWorkingDirectory(_:)` → session writes `cd <url>`.
- **Clean shutdown:** `AppDelegate.applicationShouldTerminate` collects all `TerminalManager` instances via `AppState.allTerminalManagers` (a computed property that iterates all `WindowState.terminalManager` references). Each manager's `killAllPTYs()` is called concurrently in a `TaskGroup`. Only when all PTYs have exited does `NSApp.replyToApplicationShouldTerminate(true)` fire.
- **State owned:** the PTY master `FileHandle`, the Zsh `Process` handle, the emulator screen grid, the `ScrollbackBuffer`, the cursor position, the active `TerminalProfile`, and the selection model (`selectionStart`/`selectionEnd` cell positions). Owns no file content and does not write `AppState` (read-only consumer of the window's workspace directory).
- **Text selection (ISS-059):** `TerminalTextView` tracks a drag-based selection via `mouseDown`/`mouseDragged` overrides. Selected cells are highlighted with `NSColor.selectedTextBackgroundColor` at 40% alpha. `⌘C` copies selected cells (row-joined with `\n`) to `NSPasteboard.general`. `⌘V` reads plain text from the pasteboard and forwards it as UTF-8 data to `onKeyInput`. Selection is cleared on new snapshot output and when the user presses Escape.
- **Dependencies:** Foundation 2.2 Global State (`WindowState` for per-window workspace directory + terminal manager registration); 2.3 Settings (`TerminalProfile`: font, colours, scrollback cap); 2.4 UI/UX (panel chrome, pinned-bottom slot, error dialogs); 2.6 App Lifecycle (terminate sessions on app quit via `AppState.allTerminalManagers`); `SputnikShared` (`RenderThrottle` used by `TerminalTextView`). The terminal never calls another panel directly.
- **Failure modes:**
  - `posix_openpt`/`grantpt`/`unlockpt` fails → throw `SputnikError.hardwareAccessDenied`; surface via 2.4 error dialog; panel shows a disabled placeholder; no crash, no force-unwrap (SR-2).
  - Zsh `Process` fails to launch (missing binary, sandbox denial) → catch, report, leave the panel idle and offer retry.
  - **Zombie processes** (spec 7.5) → `PTY Lifecycle Management`: `terminate()` sends `SIGTERM`, waits, then closes the master fd and nils the `Process`. The session is terminated on tab close and on app quit (driven by 2.6 App Lifecycle), so no orphaned shell survives.
  - Scrollback growth → ring buffer caps line count from the active profile; oldest lines are released (SR-3) — the buffer can never grow unbounded.
  - Master fd read returns EOF / Zsh exits → finish the `AsyncStream`, mark the session dead, show an inline "shell exited" notice, and allow restart.
  - PTY write fails (slave closed) → discard the keystroke, surface a non-fatal warning, mark the session for restart.

## Invariants
- `TerminalSession` is an **actor** — all PTY I/O is serialised through actor isolation; `send(_:)` and `resize(cols:rows:)` are actor-isolated (SW-1)
- The long-lived PTY output reader `Task(priority: .utility)` captures `[weak self]` — without this, the actor would never deallocate (SW-2, canonical PTY infinite-loop leak risk)
- Zsh `standardInput/Output/Error` are bound to the PTY **slave `FileHandle`**, never a `Pipe` (MR-4)
- `PTYHandle` checks **every POSIX call** — `posix_openpt`, `grantpt`, `unlockpt`, `ptsname` — and throws `SputnikError.hardwareAccessDenied` on failure; no force-unwraps (MR-5, SR-2)
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
