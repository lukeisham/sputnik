---
plan: Error handling 1 — structured logging and terminal session-death UX
modules: 2 Foundation (2.7 Utilities) / 7 Terminal
created: 2026-06-13
status: pending
related_issues: ISS-109, ISS-110
split_from: 2026-06-13 Error handling robustness.md (deleted 2026-06-14 after split)
---

> **Split 1 of 3** carved from the original "Error handling robustness" plan. **Land this first** —
> the `SputnikLogger` it introduces is used by the other two splits (and several existing plans) to
> log failures, so having it in place unlocks diagnosis of any regressions the watcher rewrites
> cause. Also delivers the terminal session-death banner, which depends on the logger.

## Purpose
Add a structured logging layer so non-fatal failures stop being silent (ISS-109), and surface
terminal session death to the user with a restart affordance (ISS-110).

## Success Condition
Verified by build + manual exercise:
- `swift build` clean across all packages — no new warnings in affected modules.
- In Console.app, filter for subsystem `com.sputnik.*`; after any non-fatal error path is exercised
  (e.g. saving to a read-only volume, closing a terminal tab), structured log entries appear — no
  path is silent (ISS-109).
- Killing the Zsh process in a terminal tab from another tab (`kill <pid>`) causes the terminal
  view to display "Session ended" text within the rendered grid; pressing Return restarts the
  session (ISS-110).

## Steps

### Step 1 — Add `SputnikLogger` to 2.7 Utilities (ISS-109)

**What:** Create `2 Foundation/2.7 Utilities/SputnikLogger.swift` containing:

```swift
import os

public enum SputnikLogger {
    public static let foundation = Logger(subsystem: "com.sputnik", category: "foundation")
    public static let editor     = Logger(subsystem: "com.sputnik", category: "editor")
    public static let fileTree   = Logger(subsystem: "com.sputnik", category: "fileTree")
    public static let terminal   = Logger(subsystem: "com.sputnik", category: "terminal")
    public static let preview    = Logger(subsystem: "com.sputnik", category: "preview")
}
```

Then replace every empty or comment-only `catch` in the following files with an
`os.Logger.error(...)` or `.warning(...)` call using the appropriate channel:

| File | Lines | Channel | Level |
|---|---|---|---|
| `FilePersistenceService.swift` | 47, 63, 82, 102, 123, 135, 165 | `.foundation` | `.warning` or `.error` |
| `TerminalManager.swift` | 154–157 | `.terminal` | `.warning` |
| `FileTreeViewModel.swift` | 305 | `.fileTree` | `.error` |

Message format: `"[Context] \(error)"` — short, structured, no PII.

**Why:** Without a log trail, non-fatal failures in persistence, the terminal, and the file tree
are completely invisible. `os_log` is near-zero cost when not collected (ISS-109).

> **Coordination note:** The `2026-06-13 2 FilePersistenceService correctness hardening.md` plan
> also adds an `os.Logger` to `FilePersistenceService.swift` (its step 4). Whichever lands first
> creates the logger; the second should adopt `SputnikLogger.foundation` rather than a second
> local `Logger`. If this plan lands first, prefer `SputnikLogger` everywhere and have the
> persistence plan reference it.

---

### Step 2 — Surface terminal session death to the user (ISS-110)

**What:** In `TerminalManager`, add a `@Published var sessionEndedMessage: String? = nil` property.
When the pump stream finishes (shell exited normally) or `send()` catches a write error, set it to
`"Session ended — press ↵ to restart"` and log via `SputnikLogger.terminal`. Clear it at the start
of `startSession`.

In `TerminalView`, overlay the rendered grid with a translucent banner when
`manager.sessionEndedMessage != nil`. Tapping Return / pressing `⏎` in the dead terminal calls
`manager.startSession(directory: manager.currentWorkingDirectory)`.

**Why:** Currently a dead session is indistinguishable from a live but unresponsive one. Users lose
keystrokes with no feedback (ISS-110). The terminal PTY plans own lifecycle *correctness*; this
step owns the *user-visible signal*.

---

### Step 3 — Re-verify and update Module Guides

**What:**
- Update `2 Foundation/2.7 Utilities/guide.md` (or the Foundation guide) to list `SputnikLogger`
  as a shared utility type; set `last_updated: 2026-06-13`.
- Update `1 Setup/Module Guides/7 Terminal/guide.md`: add `sessionEndedMessage` to the Technical
  Summary; set `status: active`, `last_updated: 2026-06-13`.

**Why:** The guides must match the new code so future agents have accurate context.

---

## Risks and Constraints
- **Logging-first ordering.** This split is the dependency for splits 2 and 3, which reference
  `SputnikLogger.fileTree` / `.editor` in their error paths. Land it first.
- **Terminal touch is additive.** `sessionEndedMessage` is new state read by `TerminalView`;
  it does not alter the PTY lifecycle owned by the `7a`/`7b`/`7c` plans. If those are in flight,
  confirm the pump-finish hook point still exists after their I/O rewrite.
- **No third-party packages** — `os.Logger` is system-provided (SR-5).

## Files Affected
- `2 Foundation/2.7 Utilities/SputnikLogger.swift` — new file (Step 1)
- `2 Foundation/2.5 Persistence/FilePersistenceService.swift` — add log calls (Step 1)
- `7 Terminal/TerminalManager.swift` — log calls + `sessionEndedMessage` (Steps 1, 2)
- `7 Terminal/TerminalView.swift` — dead-session overlay + Return-to-restart (Step 2)
- `6 Project File Tree/FileTreeViewModel.swift` — add log call at line 305 (Step 1)
- `1 Setup/Module Guides/7 Terminal/guide.md` — update (Step 3)
- Foundation guide / 2.7 Utilities section — `SputnikLogger` entry (Step 3)

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[2.7+7] Structured logging and terminal session-death UX`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
- [ ] Mark ISS-109, ISS-110 Resolved in Issues.md with the fix summary
