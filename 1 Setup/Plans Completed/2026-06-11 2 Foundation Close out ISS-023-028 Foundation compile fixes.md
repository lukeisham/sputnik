---
plan: Close out Foundation compile fixes ISS-023–028
module: 2 Foundation
created: 2026-06-11
status: pending
related_issues: ISS-023, ISS-024, ISS-025, ISS-026, ISS-027, ISS-028
---

## Purpose
Confirm that the six open Foundation compile-error and API-drift issues (ISS-023–028) are fully resolved in the current codebase, then document each resolution in Issues.md so the tracker is truthful.

## Success Condition
Every row for ISS-023 through ISS-028 in `1 Setup/References/Issues.md` shows a non-empty resolution note and a resolved date. The Issues.md committed and pushed. No unresolved issues in the 023–028 range.

## Steps

- [x] 1. **Confirm ISS-023 — SputnikAlert unescaped string literals**
   What: Verify `2 Foundation/2.4 UI and UX/SputnikAlert.swift` message strings escape inner double-quotes as `\"`. Current reading confirms they do (lines 40, 42, 44). No code change needed.
   Why: ISS-023 reported the literal `""\(...)""` syntax producing compile errors; commit 7b13b5b fixed it. Confirmation keeps the plan honest.

- [x] 2. **Confirm ISS-024 — Orphaned ClaudeStatusLineReader / TerminalModelDetector**
   What: Verify `2 Foundation/2.7 Utilities/ClaudeStatusLineReader.swift` and `TerminalModelDetector.swift` no longer exist on disk. Current file listing of `2 Foundation/2.7 Utilities/` confirms both are absent; Claude stats polling was migrated into `MainAIMonitor.swift`. No code change needed.
   Why: ISS-024 reported both files referencing the removed `AppState.terminalModelInfo`; commit 7b13b5b deleted them.

- [x] 3. **Confirm ISS-025 — MainAIMonitor deinit actor-isolation error**
   What: Verify `MainAIMonitor.swift` uses `@MainActor deinit` (Swift 5.9+ syntax) instead of calling `@MainActor`-isolated members from a bare `nonisolated deinit`. Current reading confirms line 87: `@MainActor deinit { … }`. No code change needed.
   Why: ISS-025 reported actor-isolation compile errors in `deinit`; commit 7b13b5b adopted `@MainActor deinit`.

- [x] 4. **Confirm ISS-026 — Assorted API drift (five sub-issues)**
   What: Verify all five drift points are absent:
   1. `SettingsStore.DefaultsKey.terminalFontName` — exists at line 150 of SettingsStore.swift. ✓
   2. `SputnikColor.accentPrimary` in DocumentTabBar — no longer referenced. ✓
   3. `HierarchicalShapeStyle.orange` in SupportingAISettingsView — no longer referenced. ✓
   4. Closure passed as `SortComparator` in SlashCommandRegistry — uses `sorted { lhs, rhs in … }` closure directly. ✓
   5. `NSApp.replyToApplicationShouldTerminate` — AppDelegate.swift line 89 uses `reply(toApplicationShouldTerminate:)`. ✓
   No code change needed.
   Why: ISS-026 catalogued five distinct compile breaks; commit 7b13b5b addressed all five.

- [x] 5. **Confirm ISS-027 — MainAIMonitor observe() data-race warning**
   What: Verify `MainAIMonitor.observe(line:)` is declared `nonisolated` so the `TerminalSession`-actor caller does not cross into `@MainActor`-isolated code. Current reading confirms line 207: `public nonisolated func observe(line: String) { lineContinuation.yield(line) }`. `AsyncStream.Continuation.yield` is `Sendable`-safe. No code change needed.
   Why: ISS-027 flagged the data-race risk; commit 7b13b5b added `nonisolated`.

- [x] 6. **Confirm ISS-028 — Window title not applied to NSWindow**
   What: Verify `ContentView.swift` applies `.navigationTitle(windowState.title)` (which SwiftUI maps to `NSWindow.title` on macOS) and that `WindowState.title` is a computed property returning `activeWorkspaceDirectory?.lastPathComponent ?? "Untitled"`. Current readings confirm both: ContentView.swift line 71 and WindowState.swift line 42. No code change needed.
   Why: ISS-028 reported the window always showing SwiftUI's default title; commit 7b13b5b wired `windowState.title`.

- [x] 7. **Update Issues.md — add resolution notes for ISS-023 through ISS-028**
   What: Edit `1 Setup/References/Issues.md` to change the Status cell for each of ISS-023, ISS-024, ISS-025, ISS-026, ISS-027, and ISS-028 from `Open` to a dated resolution note matching the pattern used by other resolved rows.
   Why: The tracker is the source of truth for known issues; leaving six "Open" rows that were fixed in commit 7b13b5b makes the log misleading and risks double-effort in future plans.

- [x] 8. **Commit, push, and move plan**
   What: Stage only `1 Setup/References/Issues.md` and this plan file. Commit with `[2 Foundation] Close out ISS-023–028 compile-fix tracker entries`. Push to GitHub. Move this plan to `Plans Completed/`.
   Why: Closes the loop on commit 7b13b5b's work; the plan file location is the final signal that the plan is done.

## Risks and Constraints
- **No code changes in this plan.** Every fix landed in commit 7b13b5b; this plan only confirms and documents. If any confirmation step reveals the fix is absent, stop, log a new ISS, and create a new plan to address it rather than silently patching here.
- **Issues.md is append-only per its own header** — do not delete or rewrite existing rows; only extend the Status cell in place.
- **Foundation boundary (SR-1):** Not applicable — this plan touches only documentation.

## Files Affected
- `1 Setup/References/Issues.md` — update Status for ISS-023 through ISS-028 to resolved

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly? Yes — all six ISS rows now have resolution notes and a resolved date in Issues.md.
- [x] Success Condition verified (ran / tested / confirmed as described above)
- [x] Module Guide(s) updated (`status` + `last_updated`) — none required for this documentation-only plan
- [x] Changes committed: `[2 Foundation] Close out ISS-023–028 compile-fix tracker entries` (commit 19fb33e)
- [x] Pushed to GitHub
- [x] Plan moved to Plans Completed/
