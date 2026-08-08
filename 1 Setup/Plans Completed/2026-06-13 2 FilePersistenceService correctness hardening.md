---
plan: FilePersistenceService correctness hardening
module: 2 Foundation (2.5 Persistence / 2.6 App Lifecycle)
created: 2026-06-13
status: completed
completed: 2026-06-14
related_issues: ISS-100, ISS-101, ISS-102, ISS-103
---

## Purpose
Fix four correctness defects in `FilePersistenceService`: layout and window state being silently
dropped on every quit (ISS-100); write ordering hazards that can resurrect recovery files the
user already cleared (ISS-101); recovery filename collisions across multi-folder sessions
(ISS-102); and I/O that claims to run off-main but actually runs on `@MainActor` (ISS-103).

## Success Condition
Verified by build + manual exercise:
- `swift build` clean across all packages — no new warnings in module 2.
- After quitting and relaunching, panel layout and open-document state are correctly restored
  — the same windows, tabs, and panel widths appear (ISS-100).
- Opening two files with the same name in different directories and editing both produces two
  distinct recovery files; closing (saving) one clears only its recovery entry (ISS-102).
- In Instruments Time Profiler, saving a 1 MB layout blob shows the `JSONEncoder.encode` and
  `data.write` work on a non-main thread (ISS-103).
- Existing module-2 and module-3 editor tests continue to pass.

## Steps

- [x] 1. **Introduce `PersistenceWriter` actor for serialised off-main writes (ISS-101, ISS-103)**
   What: Add a new file `2 Foundation/2.5 Persistence/PersistenceWriter.swift` containing:
   ```swift
   actor PersistenceWriter {
       func write<T: Encodable>(_ value: T, to url: URL) throws {
           let data = try JSONEncoder().encode(value)
           try data.write(to: url, options: .atomic)
       }
       func writeText(_ content: String, to url: URL) throws {
           try content.write(to: url, atomically: true, encoding: .utf8)
       }
       func remove(at url: URL) throws {
           guard FileManager.default.fileExists(atPath: url.path) else { return }
           try FileManager.default.removeItem(at: url)
       }
   }
   ```
   In `FilePersistenceService`, add `private let writer = PersistenceWriter()` and replace
   the three `Task(priority: .utility) { ... }` fire-and-forget blocks in `writeJSON`,
   `writeRecovery`, and `clearRecovery` with `Task { try? await self.writer.write(...) }`,
   `Task { try? await self.writer.writeText(...) }`, and `Task { try? await self.writer.remove(...) }`
   respectively.
   Why: An `actor` serialises all calls to it — concurrent `flushLayout`/`clearRecovery`
   invocations are now queued, eliminating the interleaving hazard (ISS-101). The actor
   also runs on the cooperative thread pool, not on `@MainActor`, so encode + write genuinely
   happen off the main thread (ISS-103).

- [x] 2. **Make quit-time writes synchronous (ISS-100)**
   What: Add a synchronous-flush method to `PersistenceService` protocol and implement it in
   `FilePersistenceService`:
   ```swift
   // Protocol addition
   func flushLayoutSync(_ state: LayoutState)
   func saveWindowsSync(_ descriptors: [WindowDescriptor])
   ```
   The implementations encode and write directly (no Task wrapper), since they are only called
   from `applicationWillTerminate` where async dispatch is not viable:
   ```swift
   public func flushLayoutSync(_ state: LayoutState) {
       let url = supportDirectory.appendingPathComponent(Keys.layoutFilename)
       guard let data = try? JSONEncoder().encode(state) else { return }
       try? data.write(to: url, options: .atomic)
   }
   ```
   In `AppDelegate.applicationWillTerminate`, replace the existing calls to `flushLayout` and
   `saveWindows` with `flushLayoutSync` and `saveWindowsSync`.
   The scratchpad `UserDefaults.set` calls are already synchronous — leave them unchanged.
   Why: `applicationWillTerminate` returns immediately after the method body; any
   fire-and-forget Task spawned inside it is never scheduled. Synchronous encoding +
   `data.write(atomically:)` is the only reliable path at termination time (ISS-100).

- [x] 3. **Fix recovery filename collisions — key by path hash (ISS-102)**
   What: Replace the `recoveryURL(for:)` implementation. Instead of keying on
   `lastPathComponent`, use a stable hash of the full path plus a human-readable suffix:
   ```swift
   private func recoveryURL(for url: URL) -> URL {
       let hash = String(url.path.hashValue, radix: 16, uppercase: false)
       let display = url.deletingPathExtension().lastPathComponent
       let name = "\(display)-\(hash)"
       return supportDirectory
           .appendingPathComponent(Keys.recoveryDirectory, isDirectory: true)
           .appendingPathComponent("\(name).\(Keys.recoveryExtension)")
   }
   ```
   Update `pendingRecoveryNames()` to return the full original path embedded inside the
   recovery file rather than the filename component. The simplest approach: `writeRecovery`
   prepends a header line `// source: <absolute-path>\n` before the content. Update
   `pendingRecoveryNames()` to read the first line of each `.recovery` file and return
   the path extracted from it (falling back to the filename for legacy files without the
   header). Update all call sites of `pendingRecoveryNames()` (in `AppDelegate`) accordingly.
   Why: Two open files with the same name in different directories currently map to the same
   recovery path and silently overwrite each other (ISS-102).

- [x] 4. **Log errors via `os.Logger` instead of silently swallowing them (ISS-100 related)**
   What: Import `os` at the top of `FilePersistenceService.swift`. Add:
   ```swift
   private let logger = Logger(subsystem: "com.sputnik", category: "Persistence")
   ```
   In every catch block in the file (including `createDirectoriesIfNeeded`, `PersistenceWriter`
   methods called via Task, and `flushLayoutSync`/`saveWindowsSync`), replace the empty body
   with `logger.error("...")` with a descriptive message including the error and the affected
   path. Recovery-write failures should be logged at `.error` level; layout/window failures at
   `.warning` (best-effort by design, but should be visible in Console.app).
   Why: A persistent failure (full disk, sandbox permissions change, directory creation
   failure) is currently invisible. `createDirectoriesIfNeeded` failure silently causes
   every subsequent write to fail with no diagnostic (ISS-100 related root cause).

- [x] 5. **Re-verify and update the Foundation Module Guide**
   What: After all steps pass, update `1 Setup/Module Guides/2 Foundation/guide.md` to
   reflect: (a) `PersistenceWriter` actor serialises all file writes; (b) quit-time flushing
   uses synchronous methods `flushLayoutSync`/`saveWindowsSync`; (c) recovery files are keyed
   by `<name>-<pathHash>.recovery` with a source-path header line; (d) errors are logged
   via `os.Logger`. Set `status: stable`, `last_updated: 2026-06-13`, `last_verified: 2026-06-13`.
   Why: Guides must match the code they describe (CLAUDE.md convention).

## Risks and Constraints
- **Step 2 — synchronous write at termination:** `data.write(to:options:.atomic)` is safe to
  call on `@MainActor` at termination (the process is winding down; no UI is active). The
  `.atomic` option uses `rename(2)` and is safe against partial writes. For typical layout
  payloads (~10–50 KB) this is imperceptible.
- **Step 3 — `String.hashValue` is not stable across process launches in Swift.** Use
  `Hasher` with a seed fixed to `0` or — better — a simple CRC-32 / djb2 over the UTF-8
  bytes of the path, which is stable. Do NOT use `String.hashValue` directly as it is
  randomised per-process. Alternatively, encode the path as a URL-safe base64 of its UTF-8
  bytes truncated to 16 chars — no hash collisions possible.
- **Step 3 — legacy recovery files:** existing `.recovery` files from before this change use
  the old naming scheme. The fallback in `pendingRecoveryNames()` (read first line; if no
  `// source:` header, use filename) handles them gracefully — they will be surfaced by name
  only, which matches current behaviour.
- **Step 1 — `saveSetting` Task wrapper:** `UserDefaults.set` is O(1) and thread-safe; the
  Task wrapper in `saveSetting` adds scheduler overhead for no benefit. It can be removed
  as a cleanup in the same PR (call `UserDefaults.standard.set(data, forKey:)` synchronously
  on `@MainActor`), but is not required by any of the four issues — treat it as optional.
- Does not touch modules 3–8. All changes are isolated to `2 Foundation/2.5 Persistence/`
  and `2 Foundation/2.6 App Lifecycle/AppDelegate.swift`.

## Files Affected
- `2 Foundation/2.5 Persistence/PersistenceWriter.swift` — new file (step 1)
- `2 Foundation/2.5 Persistence/FilePersistenceService.swift` — steps 1, 2, 3, 4
- `2 Foundation/2.5 Persistence/PersistenceService.swift` — step 2 (add sync protocol methods)
- `2 Foundation/2.6 App Lifecycle/AppDelegate.swift` — step 2 (use sync flush at termination); step 3 (update pendingRecoveryNames call site)
- `1 Setup/Module Guides/2 Foundation/guide.md` — step 5

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
- [x] Success Condition verified (ran / tested / confirmed as described above)
- [x] Module Guide updated (`status` + `last_updated`)
- [x] Changes committed: `[2 Foundation] FilePersistenceService correctness hardening`
- [x] Pushed to GitHub
- [x] Plan moved to Plans Completed/
- [x] Mark ISS-100, ISS-101, ISS-102, ISS-103 Resolved in Issues.md with the fix summary
