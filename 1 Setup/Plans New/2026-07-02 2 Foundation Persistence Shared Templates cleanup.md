---
plan: Persistence write-ordering, cache correctness, and force-unwrap cleanup
module: 2.5 Persistence / 2.9 Shared / 2.10 Templates
created: 2026-07-02
status: pending
related_issues: ISS-154, ISS-155, ISS-158, ISS-160
---

## Purpose
Close out the remaining small correctness and rule-compliance gaps found across `2.5 Persistence`, `2.9 Shared`, and `2.10 Templates` — deterministic write ordering, an image cache that matches its own documentation, streamed recovery-file reads, and eliminating the module's one `try!`.

## Success Condition
- Two rapid successive saves to the same persisted file (e.g. `windows.json`) always land in call order — verified with a test that issues saves in sequence and asserts the final on-disk content matches the last call, run repeatedly to rule out a race.
- `PreviewImageCache.set(_:for:)` respects the configured `maxDimension` instead of a hardcoded `2048`, and either the `generation` counter is actually used to invalidate stale in-flight loads or it is removed along with the inaccurate doc comment.
- `pendingRecoveryNames()` no longer loads full file contents into memory for large recovery files.
- No `try!`/force-unwrap remains in `TemplatePlaceholderExpander.swift`.
- `swift build` and `swift test` pass for the Foundation package.

## Steps

- [ ] 1. **Serialise writes through an ordered queue in `PersistenceWriter`**
   What: Change `PersistenceWriter` from an actor with independently-awaited methods called from fire-and-forget `Task`s, to either (a) have `FilePersistenceService` await each write directly inside a single serial `Task` per logical stream (layout, windows, recovery), or (b) have `PersistenceWriter` accept an ordered work item (closure or enum) appended to an internal `AsyncStream`/array that it drains one at a time — so writes to the same file complete in the order they were requested.
   Why: ISS-160 — today, `flushLayout`/`saveWindows`/`writeRecovery` each spawn a new unstructured `Task`; the actor prevents interleaving mid-write but two separately-spawned tasks are not guaranteed to *start* in call order, so a fast second save can finish before a slower first one, leaving stale data on disk (SR-2 — data-loss/correctness on save paths must be explicit).

- [ ] 2. **Fix `PreviewImageCache.set(_:for:)` to use `maxDimension`**
   What: Replace the hardcoded `2048` in `set(_:for:)` with `self.maxDimension` (call is already inside the actor, so this is a direct property read).
   Why: ISS-154 — changing `maxDimension` currently has no effect on images stored via `set(_:for:)`, only on the `image(for:loader:)` path, which is an inconsistency a caller wouldn't expect.

- [ ] 3. **Resolve the unused `generation` counter**
   What: Either remove `generation` entirely and correct the doc comment to describe only the actual `removeAllObjects()`-based invalidation, or make it meaningful by having in-flight `image(for:loader:)` calls capture the generation before their background load and discard (not cache) the result if the generation changed while loading.
   Why: ISS-154 — the doc comment promises "generation-based invalidation" for stale in-flight loads that doesn't exist; either implement it (useful — a slow load for a since-invalidated document could otherwise repopulate the cache with stale data) or stop claiming it (SW-4 — docs must match behavior).

- [ ] 4. **Stream the recovery-file header read instead of loading whole files**
   What: In `FilePersistenceService.pendingRecoveryNames()`, replace `String(contentsOf: fileURL, encoding: .utf8)` with a bounded read via `FileHandle` (e.g. `try FileHandle(forReadingFrom:).read(upToCount: 4096)`, decode UTF-8, and take the first line) so only a small prefix is loaded regardless of the recovered document's size.
   Why: ISS-158 — the current implementation loads the entire recovery file into memory just to read its first header line, which conflicts with SR-3 for large recovered documents.

- [ ] 5. **Remove the `try!` in `TemplatePlaceholderExpander`**
   What: Replace the `try! NSRegularExpression(pattern:)` with a `static let` built via a compile-checked Swift regex literal (`#/\{\{([^{}]+)\}\}/#` via the `Regex` API), or a lazily-initialized property that falls back to a `nil` pattern with a logged error and a no-op expansion if construction ever fails.
   Why: ISS-155 — this is the only force-unwrap-family call in the module's production code, violating SR-2's blanket "no force-unwraps in non-test code" rule even though the pattern is a compile-time constant that can't realistically fail.

- [ ] 6. **Add regression tests**
   What: Add tests to `2 Foundation/Tests/FoundationModuleTests.swift` for: ordered-write correctness (step 1), `PreviewImageCache.set` honoring `maxDimension` (step 2), and `pendingRecoveryNames()` correctness on a large synthetic recovery file (step 4).
   Why: Locks in each fix so a future refactor doesn't quietly reintroduce the race, the hardcoded constant, or the full-file read.

## Risks and Constraints
- The write-ordering fix must not reintroduce blocking on the main actor — `FilePersistenceService` methods are still called from `@MainActor` call sites and must return immediately; only the underlying completion order changes, not the fire-and-forget calling convention (SW-1, SR-4).
- If `generation`-based in-flight discard is implemented (step 3), be careful not to leak memory by holding references to superseded loader closures — keep the change minimal and actor-isolated.
- This plan does not touch Foundation's public API surface (`PersistenceService` protocol signatures are unchanged), so no other module should need edits — confirm with a full-repo build after the change.

## Files Affected
- `2 Foundation/2.5 Persistence/PersistenceWriter.swift` — ordered write queue.
- `2 Foundation/2.5 Persistence/FilePersistenceService.swift` — call-site adjustments for ordered writes; streamed recovery-name read.
- `2 Foundation/2.9 Shared/PreviewImageCache.swift` — `maxDimension` fix in `set(_:for:)`; resolve `generation` counter.
- `2 Foundation/2.10 Templates/TemplatePlaceholderExpander.swift` — remove `try!`.
- `2 Foundation/Tests/FoundationModuleTests.swift` — new/extended tests.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`) — `1 Setup/Module Guides/2 Foundation/2.5 Persistence/guide.md`, `2.9 Shared/guide.md`, `2.10 Templates/guide.md`
- [ ] Changes committed: `[2 Foundation] Persistence write-ordering, cache, and template cleanup`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
