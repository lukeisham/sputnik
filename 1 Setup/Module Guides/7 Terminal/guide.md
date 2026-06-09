---
module: 7 Terminal
status: active
last_updated: 2026-06-09
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

## Technical Summary
- **Framework(s):** Foundation (`Process`, `FileHandle`), Darwin POSIX (`posix_openpt`, `grantpt`, `unlockpt`, `ptsname`), AppKit via `NSViewRepresentable` (raw rendering per SW-3), SwiftUI, Swift Concurrency
- **Key types:**
  - `TerminalSession` — `actor` owning the PTY master `FileHandle` and the Zsh `Process`; exposes `start()`, `send(_ bytes: Data)`, `resize(cols:rows:)`, and `terminate()`; serialises all PTY I/O through actor isolation <!-- assumed -->
  - `PTYHandle` — wraps the `posix_openpt → grantpt → unlockpt → ptsname` sequence, returning the master `FileHandle` and the slave path; one responsibility, one file (SR-6) <!-- assumed -->
  - `TerminalEmulator` — parses the raw ANSI/VT byte stream into a grid of screen cells plus a capped scrollback buffer; no AppKit dependency so it is unit-testable <!-- assumed -->
  - `TerminalRenderer` — `NSViewRepresentable` drawing the emulator's cell grid; AppKit is justified here by ANSI rendering throughput (SW-3) <!-- assumed -->
  - `KeyEncoder` — translates special keys (arrows, Backspace, Delete, Ctrl-C, etc.) into the ANSI byte sequences Zsh expects (spec 7.6) <!-- assumed -->
  - `ScrollbackBuffer` — fixed-capacity ring buffer of rendered lines; drops the oldest line on overflow to cap RAM (SR-3) <!-- assumed -->
  - `TerminalProfile` — `Sendable` value type for customisation (font, colours, scrollback line limit); sourced from Settings (2.3) <!-- assumed -->
- **Per-window terminal:** Each window gets its own `TerminalManager`, stored on `WindowState.terminalManager`. `TerminalView` reads `windowState.activeWorkspaceDirectory` (not `AppState`) for the `cd` sync, and registers itself via `windowState.terminalManager = manager` on appear. This ensures each window's shell runs in its own project directory with no terminal state leaking between windows.
- **`SputnikMenuBarController`** (`@MainActor`) — observes `AppState.isProcessing` (computed, ORs all windows). Its `observation` closure captures `[weak self]`. Uses `NSStatusItem` buttons' `layer` (AppKit-only, annotated).
- **Threading model:** PTY reads are consumed as an `AsyncStream<Data>` on a long-lived `Task(priority: .utility)` captured with `[weak self]` so the session deallocates (SW-2 — this is the canonical infinite-loop leak risk). ANSI parsing runs off the main thread inside the emulator; only the final cell-grid hand-off and all `NSView` drawing occur on `@MainActor`. `cd` synchronisation observes `WindowState.activeWorkspaceDirectory` (2.2) on the main actor and writes to the PTY through the session actor.
- **Data flow:** `TerminalSession.start()` opens the PTY (`PTYHandle`), launches Zsh via `Process` with `standardInput/Output/Error` bound to the PTY slave `FileHandle` (MR-4 — never a `Pipe`) → Zsh output arrives on the master fd as `AsyncStream<Data>` → `TerminalEmulator` parses bytes into cells + scrollback → `TerminalRenderer` draws on `@MainActor`. Inbound: keystroke → `KeyEncoder` → `TerminalSession.send(_:)` → PTY master write → Zsh stdin. Directory: `windowState.activeWorkspaceDirectory` change → session writes `cd <url>`.
- **Clean shutdown:** `AppDelegate.applicationShouldTerminate` collects all `TerminalManager` instances via `AppState.allTerminalManagers` (a computed property that iterates all `WindowState.terminalManager` references). Each manager's `killAllPTYs()` is called concurrently in a `TaskGroup`. Only when all PTYs have exited does `NSApp.replyToApplicationShouldTerminate(true)` fire.
- **State owned:** the PTY master `FileHandle`, the Zsh `Process` handle, the emulator screen grid, the `ScrollbackBuffer`, the cursor position, and the active `TerminalProfile`. Owns no file content and does not write `AppState` (read-only consumer of the window's workspace directory).
- **Dependencies:** Foundation 2.2 Global State (`WindowState` for per-window workspace directory + terminal manager registration); 2.3 Settings (`TerminalProfile`: font, colours, scrollback cap); 2.4 UI/UX (panel chrome, pinned-bottom slot, error dialogs); 2.6 App Lifecycle (terminate sessions on app quit via `AppState.allTerminalManagers`). The terminal never calls another panel directly.
- **Failure modes:**
  - `posix_openpt`/`grantpt`/`unlockpt` fails → throw `SputnikError.hardwareAccessDenied`; surface via 2.4 error dialog; panel shows a disabled placeholder; no crash, no force-unwrap (SR-2).
  - Zsh `Process` fails to launch (missing binary, sandbox denial) → catch, report, leave the panel idle and offer retry.
  - **Zombie processes** (spec 7.5) → `PTY Lifecycle Management`: `terminate()` sends `SIGTERM`, waits, then closes the master fd and nils the `Process`. The session is terminated on tab close and on app quit (driven by 2.6 App Lifecycle), so no orphaned shell survives.
  - Scrollback growth → ring buffer caps line count from the active profile; oldest lines are released (SR-3) — the buffer can never grow unbounded.
  - Master fd read returns EOF / Zsh exits → finish the `AsyncStream`, mark the session dead, show an inline "shell exited" notice, and allow restart.
  - PTY write fails (slave closed) → discard the keystroke, surface a non-fatal warning, mark the session for restart.

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
