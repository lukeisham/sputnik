---
plan: Error handling robustness — logging, watcher reliability, and session-death UX
modules: 2 Foundation (2.7 Utilities) / 3 Text Editor / 6 Project File Tree / 7 Terminal
created: 2026-06-13
status: superseded
related_issues: ISS-109, ISS-110, ISS-111, ISS-112, ISS-113, ISS-114, ISS-115
---

> **Superseded — do not execute this plan directly.** It has been split into three
> smaller, independently-landable plans. Execute those instead (land the logging plan first):
> - `2026-06-13 Error handling 1 — logging and terminal session-death UX.md` (ISS-109, 110)
> - `2026-06-13 Error handling 2 — FSEventStream file-tree watcher.md` (ISS-111, 114, 115)
> - `2026-06-13 Error handling 3 — DispatchSource editor watcher.md` (ISS-111, 112, 113)
>
> Note: ISS-111 (POSIX-write detection) is closed jointly by plans 2 and 3 — the file tree
> moves to FSEventStream, the editor's single-file watch moves to DispatchSource. Mark ISS-111
> resolved only once both have landed. Retained for reference only.

## Purpose

Close seven error-handling and robustness gaps that span the app's long-running components:
add a structured logging layer (ISS-109), surface terminal session death to the user (ISS-110),
replace `NSFilePresenter`-based watchers with APIs that detect uncoordinated POSIX writes
(ISS-111), add deletion/rename handling and reload-failure feedback to the editor watcher
(ISS-112), fix the one-shot suppress flag that can fire at the wrong time (ISS-113), surface
watched-root loss in the file tree (ISS-114), and fix the data-race comment on
`FileSystemWatcher.continuation` (ISS-115).

Does **not** overlap with:
- `2026-06-13 7 Terminal PTY hardening.md` (ISS-068–079 — PTY lifecycle and I/O)
- `2026-06-13 2 FilePersistenceService correctness hardening.md` (ISS-100–103)
- `2026-06-13 3 Editor concurrency and save-safety hardening.md` (ISS-081–084)
- Any other existing plan in Plans New/

---

## Success Condition

Verified by build + manual exercise:

- `swift build` clean across all packages — no new warnings in any affected module.
- In Console.app, filter for subsystem `com.sputnik.*`; after any non-fatal error path is
  exercised (e.g. saving to a read-only volume, closing a terminal tab), structured log
  entries appear — no path is silent (ISS-109).
- Killing the Zsh process in a terminal tab from another tab (`kill <pid>`) causes the
  terminal view to display "Session ended" text within the rendered grid; pressing Return
  restarts the session (ISS-110).
- Editing a file, then running `echo "x" >> <file>` in the terminal, causes the editor to
  show the "File Changed" prompt within 1 s — `NSFilePresenter`-only detection would miss
  this (ISS-111).
- Opening a folder in the file tree, then running `rm -rf <subfolder>` in the terminal,
  causes the tree to update within 1 s (ISS-111).
- Deleting the open file from the terminal shows a "File deleted — save to new location?"
  state in the editor, not silent stale buffer (ISS-112).
- Clicking Reload when the file is gone shows an error alert, not silent no-op (ISS-112).
- Saving a file twice in quick succession never produces a spurious "File Changed" prompt
  for either save (ISS-113).
- Opening a folder, then ejecting the volume / removing the folder, shows "Folder no longer
  available" in the file tree panel and stops the watcher (ISS-114).
- `Thread Sanitizer` (Xcode → Product → Scheme → Run → Diagnostics) shows no race reports
  on `FileSystemWatcher` under concurrent stop + emit (ISS-115).

---

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

**Why:** Without a log trail, non-fatal failures in persistence, the terminal, and the file
tree are completely invisible. `os_log` is near-zero cost when not collected (ISS-109).

---

### Step 2 — Surface terminal session death to the user (ISS-110)

**What:** In `TerminalManager`, add a `@Published var sessionEndedMessage: String? = nil`
property. When the pump stream finishes (shell exited normally) or `send()` catches a write
error, set it to `"Session ended — press ↵ to restart"` and log via `SputnikLogger.terminal`.
Clear it at the start of `startSession`.

In `TerminalView`, overlay the rendered grid with a translucent banner when
`manager.sessionEndedMessage != nil`. Tapping Return / pressing `⏎` in the dead terminal
calls `manager.startSession(directory: manager.currentWorkingDirectory)`.

**Why:** Currently a dead session is indistinguishable from a live but unresponsive one.
Users lose keystrokes with no feedback (ISS-110). The terminal PTY plan owns lifecycle
*correctness*; this step owns the *user-visible signal*.

---

### Step 3 — Replace `FileSystemWatcher` with an FSEventStream watcher (ISS-111, ISS-114, ISS-115)

**What:** Replace the `NSFilePresenter`-based `FileSystemWatcher` in
`6 Project File Tree/FileSystemWatcher.swift` with an `FSEvents`-backed implementation:

```swift
public final class FileSystemWatcher: @unchecked Sendable {
    public let changeStream: AsyncStream<URL>
    private var continuation: AsyncStream<URL>.Continuation?
    private let lock = NSLock()   // guards continuation (ISS-115)
    private var eventStream: FSEventStreamRef?
    private let watchedURL: URL

    public init(url: URL) { ... }   // FSEventStreamCreate + FSEventStreamScheduleWithRunLoop
    public func stop() { ... }      // FSEventStreamStop + FSEventStreamInvalidate + continuation.finish()
}
```

Key parameters:
- `latency: 0.25` (seconds) — batches rapid bursts; matches old debounce intent.
- `flags: kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes`
- Run on a dedicated `CFRunLoop` thread owned by the watcher.
- `emit(_:)` acquires `lock` before yielding — fixes ISS-115.

For the root-deletion case (ISS-114): when the event flags contain
`kFSEventStreamEventFlagRootChanged` or `kFSEventStreamEventFlagItemRemoved` for the root
URL itself, yield a sentinel `URL(string: "sputnik://watchedRootLost")!` or add a separate
`rootLost: Bool` property set atomically. `FileTreeViewModel` observes this and transitions
to a `rootUnavailable` state that shows "Folder no longer available" in the panel header and
calls `watcher.stop()`.

**Why:** `NSFilePresenter` only fires for coordinated writes. The dominant source of external
changes in Sputnik's workflow — terminal commands (`git`, `cp`, build tools) — use POSIX
`rename`/`write` directly. `FSEventStream` is the macOS-sanctioned low-latency file-event
API that covers all writers (ISS-111). This step also fixes the continuation race (ISS-115)
and the silent-empty-tree-on-root-loss bug (ISS-114).

Update `CLAUDE.md` framework table: replace the "File system access & watching →
FileManager, FilePresenter" row with "FileManager, FilePresenter (coordinated writes), FSEventStream
(directory watch), DispatchSource file-object source (single-file watch — see ISS-111)".

---

### Step 4 — Replace `FileWatcher` with a `DispatchSource` single-file watcher (ISS-111, ISS-112, ISS-113)

**What:** Replace `3 Text Editor/3.1 Text/FileWatcher.swift` with a `DispatchSource`-based
implementation:

```swift
public final class FileWatcher: @unchecked Sendable {
    public var onChanged: (() -> Void)?   // file modified externally
    public var onDeleted: (() -> Void)?   // file deleted or moved away
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    public init(url: URL) {
        fd = open(url.path, O_EVTONLY)    // O_EVTONLY: watch without preventing unmount
        guard fd >= 0 else { return }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source?.setEventHandler { [weak self] in self?.handleEvent() }
        source?.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd) }
        }
        source?.resume()
    }

    deinit { source?.cancel() }

    public func suppressOnce() { ... }   // see below (ISS-113)
}
```

Deletion/rename handling (ISS-112): when the event mask contains `.delete` or `.rename`,
call `onDeleted?()` instead of `onChanged?()`. In `EditorViewModel`, hook `onDeleted` to set
a `@Published var fileDeletedExternally: Bool = true` flag and surface an alert: "The file
was deleted — your buffer is unsaved. Save to a new location?" with a Save As… button.

Reload-failure feedback (ISS-112): change `EditorViewModel.startWatchingFile` to propagate
the `openDocument` error rather than swallowing it with `try?`:

```swift
watcher.onChanged = { [weak self] in
    Task { @MainActor [weak self] in
        guard let self else { return }
        do {
            try await self.openDocument(url)
        } catch {
            SputnikLogger.editor.error("Reload failed for \(url.lastPathComponent): \(error)")
            self.pendingAlert = SputnikAlert.custom(
                title: "Reload Failed",
                message: error.localizedDescription
            )
        }
    }
}
```

Replace `suppressNextChange` with a generation counter (ISS-113):

```swift
private var suppressCount = 0

public func suppressOnce() { suppressCount += 1 }   // called before each save
// in handleEvent():
if suppressCount > 0 { suppressCount -= 1; return }
```

`suppressOnce()` is called once per save attempt; each notification consumes one credit.
If an atomic write produces two notifications, the second credit is consumed on the second
event — no stale flag, no false positive. If no notification arrives (POSIX rename), the
counter drains harmlessly on the next real external change (one spurious suppression at most).

**Why:** `DispatchSource` with `O_EVTONLY` detects all writers, not just coordinated ones;
`.delete`/`.rename` events surface file lifecycle changes the current implementation misses;
the generation counter eliminates the one-shot flag's misfires (ISS-111, ISS-112, ISS-113).

---

### Step 5 — Re-verify and update Module Guides + CLAUDE.md

**What:**
- Update `1 Setup/Module Guides/6 Project File Tree/guide.md`: change the Invariants and
  Technical Summary sections to reflect FSEventStream; add the `rootUnavailable` state; set
  `status: active`, `last_updated: 2026-06-13`.
- Update `1 Setup/Module Guides/7 Terminal/guide.md`: add `sessionEndedMessage` to the
  Technical Summary; set `status: active`, `last_updated: 2026-06-13`.
- Update `CLAUDE.md` framework table as noted in Step 3.
- Update `2 Foundation/2.7 Utilities/guide.md` (or the Foundation guide) to list
  `SputnikLogger` as a shared utility type.

**Why:** The guides must match the new implementations so future agents have accurate context.

---

## Risks and Constraints

- **Step 3 introduces a C-level callback** (`FSEventStreamCallback`). The callback must be a
  C function or `@convention(c)` closure; it receives a raw context pointer. Keep this
  contained entirely within `FileSystemWatcher.swift` — no leakage to callers.
- **Step 4 opens a file descriptor** with `open(O_EVTONLY)`. The fd must be closed in
  `deinit` via the `DispatchSource` cancel handler — never before, or the source fires on a
  closed fd. Verify with `leaks Sputnik` that no fd leak appears after open/close cycles.
- **Steps 3 and 4 change the API surface of the watcher types.** `FileSystemWatcher`'s
  `changeStream` AsyncStream contract is preserved (callers unchanged). `FileWatcher` gains
  `onDeleted`; existing call sites only set `onReload` — rename that to `onChanged` as part
  of this step and update `EditorViewModel.startWatchingFile`.
- **FSEventStream latency** is 0.25 s by default; the old debounce in `FileTreeViewModel`
  was also 0.3 s. Keep both — the FSEvent latency batches OS-level events, the debounce
  batches rapid refresh calls. Net latency ≈ 0.5 s, acceptable for a file tree.
- **No third-party packages** — FSEvents and DispatchSource are Darwin / Dispatch (SR-5).
- **Steps 3 and 4 are independent** — file tree and editor watcher can land separately.
  Step 1 (logging) should land first as it unlocks diagnosis of any regressions in 3/4.

---

## Files Affected

- `2 Foundation/2.7 Utilities/SputnikLogger.swift` — new file (Step 1)
- `2 Foundation/2.5 Persistence/FilePersistenceService.swift` — add log calls (Step 1)
- `7 Terminal/TerminalManager.swift` — `sessionEndedMessage`, log call (Steps 1, 2)
- `7 Terminal/TerminalView.swift` — dead-session overlay + Return-to-restart (Step 2)
- `6 Project File Tree/FileSystemWatcher.swift` — full rewrite to FSEventStream (Step 3)
- `6 Project File Tree/FileTreeViewModel.swift` — `rootUnavailable` state, root-loss handling (Step 3)
- `3 Text Editor/3.1 Text/FileWatcher.swift` — full rewrite to DispatchSource (Step 4)
- `3 Text Editor/3.1 Text/EditorViewModel.swift` — `onDeleted` hook, reload-failure alert, suppressOnce (Step 4)
- `CLAUDE.md` — framework table update (Step 3)
- `1 Setup/Module Guides/6 Project File Tree/guide.md` — update (Step 5)
- `1 Setup/Module Guides/7 Terminal/guide.md` — update (Step 5)
- Foundation guide / 2.7 Utilities section — `SputnikLogger` entry (Step 5)
