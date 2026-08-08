---
plan: Error handling 3 — DispatchSource editor watcher
module: 3 Text Editor
created: 2026-06-13
status: pending
related_issues: ISS-111b, ISS-112, ISS-113
split_from: 2026-06-13 Error handling robustness.md (deleted 2026-06-14 after split)
---

> **Split 3 of 3** carved from the original "Error handling robustness" plan. Owns the single-file
> editor watcher rewrite. Independent of split 2 (file-tree watcher) — either order — but **land
> split 1 first** so `SputnikLogger.editor` exists for the reload-failure path here.
>
> ISS-111 was split into **ISS-111a** (file tree, split 2) and **ISS-111b** (editor, this plan),
> so each maps cleanly onto one plan and can be closed independently.

## Purpose
Replace the `NSFilePresenter`-based single-file editor watcher with a `DispatchSource`-based
implementation so uncoordinated POSIX writes are detected (ISS-111b), add deletion/rename
handling and reload-failure feedback (ISS-112), and fix the one-shot suppress flag that can fire
at the wrong time (ISS-113).

## Success Condition
Verified by build + manual exercise:
- `swift build` clean across all packages — no new warnings in module 3.
- Editing a file, then running `echo "x" >> <file>` in the terminal, causes the editor to show the
  "File Changed" prompt within 1 s — `NSFilePresenter`-only detection would miss this (ISS-111b).
- Deleting the open file from the terminal shows a "File deleted — save to new location?" state in
  the editor, not a silent stale buffer (ISS-112).
- Clicking Reload when the file is gone shows an error alert, not a silent no-op (ISS-112).
- Saving a file twice in quick succession never produces a spurious "File Changed" prompt for
  either save (ISS-113).

## Steps

### Step 1 — Replace `FileWatcher` with a `DispatchSource` single-file watcher (ISS-111b, ISS-112, ISS-113)

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

**Deletion/rename handling (ISS-112):** when the event mask contains `.delete` or `.rename`, call
`onDeleted?()` instead of `onChanged?()`. In `EditorViewModel`, hook `onDeleted` to set a
`@Published var fileDeletedExternally: Bool = true` flag and surface an alert: "The file was
deleted — your buffer is unsaved. Save to a new location?" with a Save As… button.

**Reload-failure feedback (ISS-112):** change `EditorViewModel.startWatchingFile` to propagate the
`openDocument` error rather than swallowing it with `try?`:

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

**Replace `suppressNextChange` with a generation counter (ISS-113):**

```swift
private var suppressCount = 0

public func suppressOnce() { suppressCount += 1 }   // called before each save
// in handleEvent():
if suppressCount > 0 { suppressCount -= 1; return }
```

`suppressOnce()` is called once per save attempt; each notification consumes one credit. If an
atomic write produces two notifications, the second credit is consumed on the second event — no
stale flag, no false positive. If no notification arrives (POSIX rename), the counter drains
harmlessly on the next real external change (one spurious suppression at most).

**Why:** `DispatchSource` with `O_EVTONLY` detects all writers, not just coordinated ones;
`.delete`/`.rename` events surface file lifecycle changes the current implementation misses; the
generation counter eliminates the one-shot flag's misfires (ISS-111b, ISS-112, ISS-113).

### Step 2 — Re-verify and update the Module Guide

**What:** Update `1 Setup/Module Guides/3 Text Editor Window/guide.md` to reflect the
`DispatchSource`/`O_EVTONLY` single-file watcher, the `onDeleted` lifecycle hook + file-deleted
editor state, the reload-failure alert path, and the suppress-counter behaviour. Set
`status: active`, `last_updated: 2026-06-13`.

Confirm the `CLAUDE.md` framework-table row noting "DispatchSource file-object source (single-file
watch — see ISS-111b)" is present — split 2 adds it; if split 2 has not yet landed, add it here.

**Why:** The guide must match the new implementation.

## Risks and Constraints
- **Opens a file descriptor** with `open(O_EVTONLY)`. The fd must be closed in `deinit` via the
  `DispatchSource` cancel handler — never before, or the source fires on a closed fd. Verify with
  `leaks Sputnik` that no fd leak appears after open/close cycles.
- **API surface change:** `FileWatcher` gains `onDeleted`; existing call sites only set `onReload` —
  rename that to `onChanged` as part of this step and update `EditorViewModel.startWatchingFile`.
- **Depends on split 1** for `SputnikLogger.editor`. **Independent of split 2** (file-tree watcher) —
  ISS-111b (here) and ISS-111a (split 2) are separate issues and close independently.
- **Interaction with the editor save path:** `suppressOnce()` must be called by `save()`/`saveAs()`
  before the write. If `2026-06-13 3 Editor concurrency and save-safety hardening.md` (which moves
  the save off-main and switches to `FileManager.replaceItemAt`) is in flight, coordinate so
  `suppressOnce()` is called on the main actor before the detached write begins.
- **No third-party packages** — DispatchSource is Dispatch (SR-5).

## Files Affected
- `3 Text Editor/3.1 Text/FileWatcher.swift` — full rewrite to DispatchSource (Step 1)
- `3 Text Editor/3.1 Text/EditorViewModel.swift` — `onDeleted` hook, reload-failure alert, `suppressOnce` (Step 1)
- `CLAUDE.md` — framework table row (Step 2, if not already added by split 2)
- `1 Setup/Module Guides/3 Text Editor Window/guide.md` — update (Step 2)

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide updated (`status` + `last_updated`)
- [ ] Changes committed: `[3 Editor] DispatchSource file watcher — POSIX-write detection, delete/reload UX`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
- [ ] Mark ISS-111b, ISS-112, ISS-113 Resolved in Issues.md with the fix summary (ISS-111a stays open for split 2; close the parent ISS-111 once both sub-issues are resolved)
