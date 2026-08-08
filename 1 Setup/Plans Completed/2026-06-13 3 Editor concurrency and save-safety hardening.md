---
plan: Editor concurrency and save-safety hardening
module: 3 Text Editor / 8 HTML Preview
created: 2026-06-13
status: pending
related_issues: ISS-081, ISS-082, ISS-083, ISS-084
---

## Purpose
Fix four concurrency and data-safety defects in the editor and HTML preview: file I/O that erroneously blocks the main thread, a deinit that can crash via `assumeIsolated`, an unsafe two-step save that can lose the file on crash, and redundant actor hops that add latency.

## Success Condition
Verified by build + manual exercise:
- `swift build` clean across all packages (no new warnings in modules 3 or 8).
- Existing editor and HTML-preview tests pass; new tests for save/saveAs and the deinit guard pass.
- Saving a 10 MB file (`time cp /dev/urandom ~/big.txt`) does not stall the UI — editor remains interactive during the write (ISS-081).
- Force-quitting the app mid-save leaves either the original file intact or the new version intact — never a missing or zero-byte file (ISS-083).
- Running `leaks Sputnik` after opening and closing 20 documents shows no `EditorViewModel` leaks (ISS-082).
- HTML preview body update fires in the same run-loop cycle as the throttle expiry, not the next (ISS-084, observable by adding a `print` timestamp on both sides).

## Steps

- [ ] 1. **Move file I/O onto a detached background task**
   What: In `EditorViewModel.openDocument(_:)`, `save()`, and `saveAs(to:)` replace `Task(priority:) { ... }` with `Task.detached(priority:) { ... }`. Before entering each detached block, snapshot any `@MainActor` properties used inside it (particularly `loadedText` in `save()`/`saveAs()`) into local `let` constants on the main actor. Remove the now-correct-but-misleading `await MainActor.run { ... }` wrappers around the `@MainActor` state updates that follow each block (they were already no-ops, but are now genuinely off-main-then-back).
   Why: `Task(priority:)` inherits `@MainActor` from its enclosing context; all disk I/O currently blocks the main thread. `Task.detached` breaks the isolation and runs on the global executor (ISS-081). This is the documented "off-thread" pattern used correctly in `PDFViewerViewModel`.

- [ ] 2. **Fix the safe-save implementation**
   What: Replace the three-step `write(tmp) → remove(original) → move(tmp)` sequence in `save()` with a single `FileManager.replaceItemAt(_:withItemAt:backupItemName:options:)` call. The `backupItemName` parameter ensures the original is backed up before replacement — if the process crashes between steps, the file system leaves either the original or the new version, never nothing. Update `saveAs(to:)` similarly (`write(to:atomically:encoding:)` with `atomically: true` already uses `rename(2)`, so it is safe; verify and document it).
   Why: The current `remove → move` sequence has a window where both files are absent; a crash there loses the document (ISS-083).

- [ ] 3. **Eliminate `assumeIsolated` from `deinit`**
   What: In `EditorViewModel.deinit`, remove `MainActor.assumeIsolated { ... }`. Assess each cleanup call:
   - `stopWatchingFile()` — calls `fileWatcher = nil`; the `FileWatcher` deinit calls `NSFileCoordinator.removeFilePresenter`, which is thread-safe. Make `stopWatchingFile()` `nonisolated` or make it safe to call from any thread.
   - `stopRecoveryWrite()` — calls `recoveryDebounceTask?.cancel()`. `Task.cancel()` is safe to call from any isolation context; make the method `nonisolated`.
   - `resignUserActivity()` — calls `NSUserActivity.resignCurrent()`. The docs do not restrict this to any specific thread; make the method `nonisolated`.
   Apply the same fix to `FileTreeQuickLookController`: extract the `assumeIsolated` blocks in the `QLPreviewPanel` datasource callbacks into `nonisolated` helpers that read state safely (either via a lock or by documenting the QuickLook guarantee that callbacks arrive on the main thread, and using `precondition(Thread.isMainThread)` instead of `assumeIsolated`).
   Why: `deinit` is not actor-isolated; a background task holding the last strong reference makes `assumeIsolated` trap and crash (ISS-082).

- [ ] 4. **Remove redundant inner `Task { @MainActor in ... }` in `HTMLPreviewCoordinator.throttledLoad`**
   What: In `HTMLPreviewCoordinator.throttledLoad`, the `renderThrottle.throttle { [weak self] in ... }` closure already executes on `@MainActor` (per `RenderThrottle.throttle`'s contract). Remove the wrapping `Task { @MainActor in ... }` inside it; call `splitHTML`, `updateBodyInPlace`, and `loadHTMLString` directly. Keep the `guard let self` weak-capture pattern.
   Why: The inner Task adds a scheduler round-trip, delaying the body-content update by one run-loop cycle and obscuring the actor ownership (ISS-084).

- [ ] 5. **Remove redundant `await MainActor.run` in `TerminalManager.pumpTask`**
   What: In `TerminalManager.startSession`, `pumpTask` is `Task { [weak self] in ... }`. Because `TerminalManager` is `@MainActor`, this unstructured task inherits main-actor isolation — the `await MainActor.run { self.snapshot = snap }` and `await MainActor.run { self.isRunning = false; self.snapshot = finalSnap }` calls are unnecessary hops. Replace them with direct property assignments. Add a comment explaining that the Task inherits `@MainActor` from `self`.
   Why: Redundant actor hops add latency on every terminal output chunk (ISS-084).

- [ ] 6. **Add tests**
   What:
   - `EditorViewModelTests.testSaveDoesNotBlockMainActor`: starts a save of a large string, immediately dispatches a main-actor check, asserts the check completes before the save finishes.
   - `EditorViewModelTests.testSaveSurvivesMidWriteCrash`: mock `FileManager.replaceItemAt` to throw after backup — assert the original file is still intact.
   - `EditorViewModelTests.testDeinitFromBackgroundThread`: allocates an `EditorViewModel`, releases it from a `Task.detached` block, asserts no crash.
   Why: The three bugs fixed in steps 1–3 are easy to regress silently; tests lock them in.

- [ ] 7. **Re-verify and update the Module Guides**
   What: After all steps pass, update `1 Setup/Module Guides/3 Text Editor Window/guide.md` to reflect: (a) `save()`/`openDocument()` use `Task.detached`; (b) `deinit` cleanup methods are `nonisolated`; (c) save uses `FileManager.replaceItemAt`. Update `1 Setup/Module Guides/8 HTML Preview/guide.md` to reflect the `throttledLoad` simplification. Set `status: stable`, `last_updated: 2026-06-13`, `last_verified: 2026-06-13`.
   Why: Guides must match the code they describe; drifted guides lead to future bugs (CLAUDE.md convention).

## Risks and Constraints
- **Step 1 — capturing `loadedText` off-main:** `loadedText` is a `@MainActor` property. After moving the write to `Task.detached`, it must be snapshotted into a `let text = loadedText` on the main actor *before* entering the detached block — do not access `self.loadedText` inside the detached closure directly or the compiler will error.
- **Step 2 — `FileManager.replaceItemAt` on older macOS:** available from macOS 10.6; no deployment risk.
- **Step 3 — `nonisolated deinit`:** Swift does not allow `@MainActor` on `deinit`. Making helpers `nonisolated` is the only portable path short of scheduling cleanup via a `Task` (which adds its own risks). Prefer `nonisolated` + thread-safety audit.
- Steps 1–3 touch `EditorViewModel` — run the full editor test suite after each step, not just at the end.
- Does not touch module 7 — terminal issues remain scoped to the existing PTY hardening plan (ISS-068–079).

## Files Affected
- `3 Text Editor/3.1 Text/EditorViewModel.swift` — steps 1, 2, 3.
- `6 Project File Tree/FileTreeQuickLookController.swift` — step 3 (`assumeIsolated` fix).
- `8 HTML Preview/HTMLPreviewCoordinator.swift` — step 4.
- `7 Terminal/TerminalManager.swift` — step 5 (minor; MainActor.run removal only).
- `3 Text Editor/3.1 Text/Tests/EditorViewModelTests.swift` (or equivalent) — step 6.
- `1 Setup/Module Guides/3 Text Editor Window/guide.md` — step 7.
- `1 Setup/Module Guides/8 HTML Preview/guide.md` — step 7.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[3 Editor, 8 HTML] Concurrency and save-safety hardening`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
- [ ] Mark ISS-081, ISS-082, ISS-083, ISS-084 Resolved in Issues.md with the fix summary
