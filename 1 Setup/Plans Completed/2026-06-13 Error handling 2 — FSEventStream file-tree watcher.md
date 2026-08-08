---
plan: Error handling 2 — FSEventStream file-tree watcher
module: 6 Project File Tree
created: 2026-06-13
status: pending
related_issues: ISS-111a, ISS-114, ISS-115
split_from: 2026-06-13 Error handling robustness.md (deleted 2026-06-14 after split)
---

> **Split 2 of 3** carved from the original "Error handling robustness" plan. Owns the file-tree
> watcher rewrite. Independent of split 3 (editor watcher) — they can land in either order — but
> **land split 1 first** so `SputnikLogger.fileTree` exists for the error paths here.
>
> ISS-111 was split into **ISS-111a** (file tree, this plan) and **ISS-111b** (editor, split 3),
> so each maps cleanly onto one plan and can be closed independently.

## Purpose
Replace the `NSFilePresenter`-based file-tree watcher with an `FSEventStream`-backed
implementation so uncoordinated POSIX writes from the terminal (`git`, `cp`, `rm -rf`, build
tools) are detected (ISS-111a), surface watched-root loss to the user (ISS-114), and fix the
data race on `FileSystemWatcher.continuation` (ISS-115).

## Success Condition
Verified by build + manual exercise:
- `swift build` clean across all packages — no new warnings in module 6.
- Opening a folder in the file tree, then running `rm -rf <subfolder>` in the terminal, causes the
  tree to update within 1 s (ISS-111a).
- Opening a folder, then ejecting the volume / removing the folder, shows "Folder no longer
  available" in the file tree panel and stops the watcher (ISS-114).
- `Thread Sanitizer` shows no race reports on `FileSystemWatcher` under concurrent stop + emit
  (ISS-115).

## Steps

### Step 1 — Replace `FileSystemWatcher` with an FSEventStream watcher (ISS-111a, ISS-114, ISS-115)

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
`kFSEventStreamEventFlagRootChanged` or `kFSEventStreamEventFlagItemRemoved` for the root URL
itself, yield a sentinel `URL(string: "sputnik://watchedRootLost")!` or add a separate
`rootLost: Bool` property set atomically. `FileTreeViewModel` observes this and transitions to a
`rootUnavailable` state that shows "Folder no longer available" in the panel header and calls
`watcher.stop()`.

Log watcher setup/teardown failures via `SputnikLogger.fileTree` (from split 1).

**Why:** `NSFilePresenter` only fires for coordinated writes. The dominant source of external
changes in Sputnik's workflow — terminal commands — use POSIX `rename`/`write` directly.
`FSEventStream` is the macOS-sanctioned low-latency file-event API that covers all writers
(ISS-111a). This step also fixes the continuation race (ISS-115) and the silent-empty-tree-on-
root-loss bug (ISS-114).

### Step 2 — Update `FileTreeViewModel` for the root-loss state (ISS-114)

**What:** Add a `rootUnavailable` state to `FileTreeViewModel`. When the watcher signals root loss,
transition the panel into this state (header shows "Folder no longer available"), stop the watcher,
and clear the tree without treating it as a normal empty directory.

**Why:** Without this the tree silently shows an empty folder when the root disappears, which is
indistinguishable from a genuinely empty directory (ISS-114).

### Step 3 — Re-verify and update the Module Guide + CLAUDE.md

**What:**
- Update `1 Setup/Module Guides/6 Project File Tree/guide.md`: change the Invariants and Technical
  Summary sections to reflect FSEventStream; add the `rootUnavailable` state; set `status: active`,
  `last_updated: 2026-06-13`.
- Update `CLAUDE.md` framework table: replace the "File system access & watching → FileManager,
  FilePresenter" row with "FileManager, FilePresenter (coordinated writes), FSEventStream
  (directory watch), DispatchSource file-object source (single-file watch — see ISS-111)".

**Why:** The guide and framework table must match the new implementation.

## Risks and Constraints
- **Introduces a C-level callback** (`FSEventStreamCallback`). The callback must be a C function or
  `@convention(c)` closure; it receives a raw context pointer. Keep this contained entirely within
  `FileSystemWatcher.swift` — no leakage to callers.
- **`changeStream` AsyncStream contract is preserved** — existing callers are unchanged apart from
  observing the new root-loss signal.
- **FSEventStream latency** is 0.25 s; the old debounce in `FileTreeViewModel` was ~0.3 s. Keep
  both — the FSEvent latency batches OS-level events, the debounce batches rapid refresh calls.
  Net latency ≈ 0.5 s, acceptable for a file tree.
- **Depends on split 1** for `SputnikLogger.fileTree`. **Independent of split 3** (editor watcher) —
  ISS-111a (here) and ISS-111b (split 3) are separate issues and close independently.
- **No third-party packages** — FSEvents is Darwin (SR-5).

## Files Affected
- `6 Project File Tree/FileSystemWatcher.swift` — full rewrite to FSEventStream (Step 1)
- `6 Project File Tree/FileTreeViewModel.swift` — `rootUnavailable` state, root-loss handling (Steps 1, 2)
- `CLAUDE.md` — framework table update (Step 3)
- `1 Setup/Module Guides/6 Project File Tree/guide.md` — update (Step 3)

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide updated (`status` + `last_updated`); CLAUDE.md framework table updated
- [ ] Changes committed: `[6 File Tree] FSEventStream watcher — POSIX-write detection and root-loss UX`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
- [ ] Mark ISS-111a, ISS-114, ISS-115 Resolved in Issues.md with the fix summary (ISS-111b stays open for split 3; close the parent ISS-111 once both sub-issues are resolved)
