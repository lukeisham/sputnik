---
plan: Terminal improvements — editor↔terminal integration & multi-terminal sessions
module: 7 Terminal + 2 Foundation (2.1 Inter-panel / 2.2 Global State / 2.6 Lifecycle) + 3 Text Editor
created: 2026-06-12
status: draft
related_issues: (log via !TrackIssues before implementation — see Risks)
---

## Purpose
Make the integrated terminal a first-class participant in the workflow: let the editor push selected text and file-aware commands into the shell and pull terminal output back into the editor, and let a single window host several concurrent shell sessions via an in-slot tab strip.

## Background — what already exists (verified 2026-06-12)
Both requested features are confirmed **absent**; nothing in this plan duplicates existing code:

- **No editor↔terminal integration.** The only cross-module entry point to the terminal is `TerminalLifecycle` (2.6), which exposes a single method, `killAllPTYs()`. `InterPanelRouter` (2.1) has `open`, `close`, `syncDirectory`, `moveActiveTabToNewWindow` — nothing that sends text or commands to the shell, and nothing that captures shell output. `TerminalManager.send(_:)` exists but is reachable only from within module 7 (the view's keystroke path); Foundation holds the manager only as `any TerminalLifecycle`, so it cannot call `send`.
- **No multi-terminal.** `TerminalView` owns one `@StateObject TerminalManager`, and `WindowState.terminalManager` is a single optional. `AppState.allTerminalManagers` assumes one manager per window. There is no terminal tab bar and no session collection.
- **What we can build on:** `TerminalSession` (actor) already has `send(_:)`, `resize`, `terminate`, and an `AsyncStream<Data>` output. The terminal already supports text selection + `⌘C` (ISS-059). The editor exposes `EditorViewModel.textView` / `selectedRange()` and the active document via `windowState.activeDocument`. Spec 7.5 already says PTYs must be cleaned up "when a terminal **tab** … closes" — i.e. tabs are anticipated by the spec.

## Success Condition
**Integration**
- With text selected in the editor, a command (menu item + shortcut) sends that text to the active terminal session's stdin; with nothing selected, it sends the current line.
- A "Run on current file" command builds a shell command referencing the active document's path (correctly escaped) and runs it in the terminal — no-op with a clear message when there is no active file.
- The user can insert the terminal's current selection (or, as a fallback, the last N scrollback lines) into the editor at the cursor.
- The user can insert **the output of the last-run command** into the editor — captured precisely via shell-integration markers (the emulator tracks command/output boundaries), not by guessing line counts.
- The editor never imports module 7; all routing flows through a Foundation protocol (SR-1). No `AppState`/`WindowState` writes from the terminal.

**Multi-terminal**
- A tab strip inside the pinned terminal slot lets the user add (`⌘T`-style), switch, and close shell sessions in one window; each tab is an independent Zsh PTY with its own scrollback and working directory.
- Closing a tab terminates exactly that PTY (no zombies, spec 7.5); closing the last tab leaves a restartable empty state.
- App quit and window close still terminate **every** session via `AppState.allTerminalManagers` (updated to collect all sessions).
- No force-unwraps; per-window isolation and the existing focus/resize/`cd`-sync behaviour are preserved per session.

## Steps

### Workstream A — Editor ↔ Terminal integration (2.1 / 2.6 / 3 / 7)

- [ ] 1. **Define a `TerminalCommanding` protocol in Foundation.**
   What: Add a protocol (alongside `TerminalLifecycle` in 2.6, or in 2.1) exposing `sendText(_ String)`, `sendCommand(_ String)` (text + trailing newline to execute), and `currentSelectionText() -> String?`. Have `TerminalManager` conform. Store the active manager on `WindowState` as this richer type (or add a parallel reference) so Foundation can reach `send` without module 3 or 2 importing module 7 (SR-1).
   Why: Today Foundation only holds `any TerminalLifecycle` (`killAllPTYs()` only). A dedicated command protocol is the seam that lets the editor drive the terminal while keeping the modules decoupled — the same pattern `TerminalLifecycle` already uses for shutdown.

- [ ] 2. **Add router methods for editor→terminal actions.**
   What: Extend `InterPanelRouter` (2.1) with `sendToTerminal(_ text: String)` and `runInTerminal(_ command: String)`, implemented in `AppInterPanelRouter` by resolving the active window's terminal via the Step 1 protocol and focusing the terminal panel via `PanelFocusCoordinator`.
   Why: The router is the established single funnel for cross-panel actions (`open`/`close`/`syncDirectory`); routing here means the editor calls one well-known API and never reaches into the terminal directly.

- [ ] 3. **Add the editor-side commands ("Send selection", "Run on current file").**
   What: In `EditorViewModel` (via the existing `EditorCommandHandling` pattern), add `sendSelectionToTerminal()` — uses `textView.selectedRange()`, falling back to the current line when empty — and `runCurrentFileInTerminal()` — builds a command from `windowState.activeDocument` URL (shell-escaped, reusing the `shellEscaped` helper pattern) and calls the router. Guard cleanly when there is no text view or no active file.
   Why: These are the two concrete "push" actions requested; building them on `selectedRange()` and `activeDocument` (both already present) keeps them small and avoids new editor state.

- [ ] 4. **Add "Insert terminal selection into editor".**
   What: Add a pull action: insert the terminal's current selection (ISS-059 selection model already exists) at the editor cursor; if there is no selection, fall back to the last N scrollback lines from the active session's snapshot. Expose `currentSelectionText()` via the Step 1 protocol; insert through the editor's existing insert path.
   Why: The always-available baseline pull action — works regardless of shell configuration, since it reads whatever is on screen.

- [ ] 5. **Parse OSC 133 shell-integration markers in the emulator.**
   What: Extend `ANSIParser` to recognise the OSC 133 sequences — `133;A` (prompt start), `133;B` (command start / pre-execution), `133;C` (output start), `133;D[;exit]` (command finished) — and add a `TerminalOp` case for each. In `TerminalEmulator`, track the current command's output region (start row/col at `C`, end at the next `D`) and the last completed command's captured output text + exit code, exposing them on `EmulatorSnapshot` (Sendable). Unknown/!OSC-133 OSC payloads keep their current handling (title etc.) — this is purely additive.
   Why: Precise per-command capture needs explicit command/output boundaries; OSC 133 is the de-facto standard (iTerm2/VS Code/WezTerm shell integration) and lets the emulator know exactly where a command's output begins and ends instead of guessing.

- [ ] 6. **Emit OSC 133 from the session's shell and add "Insert last command output".**
   What: Seed the Zsh session with shell-integration hooks that emit OSC 133 around the prompt and command execution (a `precmd`/`preexec` snippet sourced at session start — written to a temp rc or injected into the PTY on launch, gated so the user's own `.zshrc` still loads). Add `lastCommandOutput() -> String?` to the `TerminalCommanding` protocol, backed by the Step 5 tracking, and a command/menu action that inserts it at the editor cursor. Fall back to the Step 4 selection path when no marked command is available (integration not yet active, e.g. first prompt).
   Why: The emulator can only track boundaries the shell announces; emitting OSC 133 from our managed Zsh session is what makes "the output of the command I just ran" exact. Graceful fallback means the feature degrades to selection-insert rather than breaking when markers are absent.

- [ ] 7. **Wire menu items + shortcuts.**
   What: Add the four commands (send selection, run on current file, insert selection, insert last command output) to the menu bar (`SputnikCommands` / the relevant command group) with shortcuts and correct enable/disable validation (disabled when no editor focus / no active file / terminal unavailable / no captured output). Mirror in any context menus where it fits.
   Why: The features are only discoverable and usable once surfaced in the menu system with proper validation; matches how Save/Render-as-HTML are exposed.

### Workstream B — Multi-terminal sessions (7 / 2.2 / 2.6)

- [ ] 8. **Introduce a per-window session collection.**
   What: Replace the single `WindowState.terminalManager` with an ordered collection (e.g. `terminalManagers: [TerminalManager]` plus an `activeTerminalID`), or add a small `TerminalGroup` owner. Each entry is an independent `TerminalManager`/`TerminalSession` with its own scrollback and working directory. Keep one active session bound to the visible renderer.
   Why: Multi-terminal is fundamentally "more than one manager per window"; the session is already self-contained, so the change is about ownership/identity, not rewriting the PTY layer.

- [ ] 9. **Add a terminal tab strip inside the pinned slot.**
   What: In `TerminalView`, render a compact tab bar above the terminal surface: one tab per session, a "+" to spawn a new session (rooted at `activeWorkspaceDirectory`), per-tab close, and active-tab highlight. Switching tabs swaps which manager's `snapshot` feeds `TerminalRenderer`. The terminal stays pinned to the bottom slot (2.4) — tabs multiplex within it, they do not relocate it.
   Why: The pinned slot is single per the layout invariant, so multiple sessions must be multiplexed in-place; spec 7.5 already references a "terminal tab", so this realises an anticipated design.

- [ ] 10. **Make session teardown tab-aware (spec 7.5).**
   What: Closing a tab calls that manager's `killAllPTYs()`/`stopSession()` and removes it; closing the last tab leaves the existing restartable empty state. Ensure focus moves to a neighbouring tab on close.
   Why: Spec 7.5 explicitly requires killing the PTY when a tab closes; without per-tab teardown, closing a tab would orphan a Zsh process (zombie).

- [ ] 11. **Update clean-shutdown collection to cover all sessions.**
   What: Update `AppState.allTerminalManagers` (2.2) and `AppDelegate` shutdown so they iterate **every** session in every window's collection (currently `compactMap { $0.terminalManager }` assumes one). Verify the `TaskGroup` concurrent-kill path still fires for all PTYs.
   Why: The quit-time guarantee ("only terminate once all PTYs exit") must not silently regress to killing one-of-N when a window has multiple tabs.

### Workstream C — Guides & issues

- [ ] 12. **Log the gaps as feature issues, then update guides.**
   What: Via `!TrackIssues`, log (a) "no editor↔terminal integration path" and (b) "terminal is single-session; spec 7.5 anticipates tabs" (next IDs are ISS-062+). Then update the **7 Terminal** guide (new `TerminalCommanding` protocol, OSC 133 shell integration + command-output capture, multi-session ownership, tab strip, tab-aware teardown) and the **2.1 / 2.6** notes (new router methods, lifecycle collection). Bump `last_updated` / `last_verified`.
   Why: Per CLAUDE.md conventions — issue first, fix second; the 7 Terminal guide is currently `stable` and must be re-marked/updated so it doesn't diverge from this change.

## Risks and Constraints
- **Touches Foundation (module 2) — flagged per the `!GenerateAPlan` rule.** New protocol + router methods (2.1/2.6) and the `allTerminalManagers` change (2.2) affect lifecycle and every window; re-verify the quit path (`applicationShouldTerminate` → `TaskGroup` → `replyToApplicationShouldTerminate`).
- **SR-1 (modular decoupling):** module 3 (editor) must NOT import module 7. All editor→terminal calls go through the Foundation `TerminalCommanding` protocol + `InterPanelRouter`, mirroring `TerminalLifecycle`.
- **Command-output capture depends on shell integration.** True "insert the output of the command I just ran" (Steps 5–6) relies on OSC 133 markers emitted by the shell; it works only in the app's managed Zsh session where we inject the hooks, and only after the first marked prompt. It must degrade gracefully to the Step 4 selection/scrollback path when markers are absent (integration off, non-Zsh, or pre-first-prompt) — never error. The injected `precmd`/`preexec` hooks must not clobber the user's own `.zshrc` hooks (append, don't replace) and must be robust to the user overriding `PROMPT`.
- **OSC parsing must stay additive (SR-2).** The new `133;A/B/C/D` handling in `ANSIParser` must not regress existing OSC title parsing or alt-screen handling; malformed or partial 133 payloads (split across PTY reads) must be tolerated without crashing or corrupting the grid.
- **Spec 7.5 / no zombies:** every new session must be terminated on tab close, window close, and app quit. `TerminalSession` teardown (`SIGTERM` → close master fd → nil `Process`) must run per tab (Steps 8–9); no force-unwraps on the PTY/process handles (SR-2).
- **Per-window isolation must hold per session:** each tab keeps its own `cd` sync against `WindowState.activeWorkspaceDirectory`, its own scrollback ring buffer (SR-3), and its own resize seeding. Confirm the focus ring + first-responder path (ISS-021) still targets the *active* session's view.
- **Threading invariants unchanged:** `TerminalSession`/`TerminalEmulator` stay actors; the PTY reader `Task` keeps `[weak self]` (SW-2) for every session; only `EmulatorSnapshot` crosses the actor boundary (SW-1). More sessions = more reader tasks — verify no retain cycle is introduced by the new collection.
- **Shell escaping:** "Run on current file" must escape the path (reuse the existing single-quote `shellEscaped` helper in `TerminalManager.swift`); never interpolate a raw path into a command string.

## Files Affected
- `2 Foundation/2.6 App Lifecycle/TerminalLifecycle.swift` (or a new `TerminalCommanding.swift` in 2.1) — new command protocol incl. `lastCommandOutput()` (Steps 1, 6).
- `7 Terminal/TerminalManager.swift` — conform to `TerminalCommanding`; expose `sendText`/`sendCommand`/`currentSelectionText`/`lastCommandOutput`; inject OSC 133 shell-integration hooks at session start (Steps 1, 4, 6).
- `7 Terminal/ANSIParser.swift` — parse OSC `133;A/B/C/D`; new `TerminalOp` cases (Step 5).
- `7 Terminal/TerminalEmulator.swift` — track command/output regions + last command output & exit code; surface on `EmulatorSnapshot` (Step 5).
- `7 Terminal/TerminalSession.swift` — source/inject the shell-integration rc on launch without suppressing the user's `.zshrc` (Step 6).
- `2 Foundation/2.2 Global State Management/WindowState.swift` — session collection + `activeTerminalID`; richer terminal reference (Steps 1, 6).
- `2 Foundation/2.2 Global State Management/AppState.swift` — `allTerminalManagers` iterates all sessions (Step 9).
- `2 Foundation/2.1 Inter-panel communication/InterPanelRouter.swift`, `AppInterPanelRouter.swift` — `sendToTerminal` / `runInTerminal` (Step 2).
- `3 Text Editor/3.1 Text/EditorViewModel.swift` — `sendSelectionToTerminal`, `runCurrentFileInTerminal`, insert-selection, insert-last-command-output (Steps 3–4, 6).
- `7 Terminal/TerminalView.swift` — terminal tab strip; swap active manager into `TerminalRenderer` (Steps 9–10).
- `2 Foundation/2.0 App Overview/SputnikCommands.swift` (+ relevant command group / context menus) — menu items, shortcuts, validation (Steps 7, 9).
- `2 Foundation/2.6 App Lifecycle/AppDelegate.swift` — multi-session shutdown verification (Step 11).
- Guides: `1 Setup/Module Guides/7 Terminal/guide.md`, `…/2 Foundation/2.1`, `…/2.6`; `1 Setup/References/Issues.md` (Step 10).
