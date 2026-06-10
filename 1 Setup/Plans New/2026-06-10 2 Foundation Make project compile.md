---
plan: Make the project compile — fix Foundation build errors
module: 2 Foundation
created: 2026-06-10
status: pending
related_issues: ISS-023, ISS-024, ISS-025, ISS-026, ISS-027, ISS-028, ISS-029
flag: TOUCHES FOUNDATION (module 2) — changes here affect every other module; Step 9 also touches module 6 (file tree)
---

## Purpose
Get the whole app ready to build by fixing the ~30 compile errors that all live in module 2 Foundation, so dependent modules (Terminal included) are ready as well. 

## Success Condition
- From the repo root: `swift build` for the `SputnikApp` executable completes with **0 errors**.
- `swift build --package-path "7 Terminal"` completes with 0 errors (proves the Terminal dependency chain links).
- No new force-unwraps or `DispatchQueue`-based business logic introduced (SR-2 / SW-1).

## Background
A diagnostic build on 2026-06-10 produced 30 unique error sites, **all in `2 Foundation`**; the 7 Terminal module's own source compiled clean. The errors cluster into four root causes (logged as ISS-023…026). Several trace to the unfinished ISS-015/016 AI-role refactor (the `terminalModelInfo` → `mainAIState` rename) leaving orphaned files behind.

## Steps

- [ ] 1. **Escape the inner quotes in `SputnikAlert.message` (ISS-023)**
   What: In `2 Foundation/2.4 UI and UX/SputnikAlert.swift`, fix each `return ""\(…)" …"` so the literal filename quotes are escaped: `return "\"\(url.lastPathComponent)\" …"`. Apply to every affected case in the `message` switch.
   Why: The unescaped leading `"` closes the string immediately, so the interpolation is parsed as loose code — 12 of the 30 errors. Escaping restores valid string literals.

- [ ] 2. **Remove the orphaned AI-detection files (ISS-024)**
   What: Confirm `MainAIMonitor.swift` fully supersedes `2 Foundation/2.7 Utilities/ClaudeStatusLineReader.swift` and `TerminalModelDetector.swift` (its header states it "migrated from ClaudeStatusLineReader"), then delete both orphans and any `Package.swift`/reference that names them. Grep the repo for remaining usages first.
   Why: Both files reference `AppState.terminalModelInfo`, removed in the ISS-015/016 refactor; they are dead duplicates of the live monitor (SR-6) and account for 8 errors.

- [ ] 3. **Fix actor isolation in `MainAIMonitor.deinit` (ISS-025)**
   What: In `2 Foundation/2.7 Utilities/MainAIMonitor.swift`, stop calling main-actor-isolated members (`processingTask`, `stopStatsPolling()`, `stopFileWatcher()`) from the nonisolated `deinit`. Capture the cancellables locally / restructure teardown so cancellation does not cross the actor boundary (e.g. cancel the `Task` handle directly, which is `Sendable`).
   Why: Swift strict concurrency forbids touching `@MainActor` state from `deinit`; this is required for the file to compile (SW-1).

- [ ] 4. **Repair the Settings/UI/Lifecycle API drift (ISS-026)**
   What:
   • `SettingsStore.swift` — add the missing `terminalFontName` (and any sibling terminal keys) to `DefaultsKey`, matching the fields `TerminalView` already reads.
   • `DocumentTabBar.swift` — replace `SputnikColor.accentPrimary` with the actual accent token defined in 2.3, or add the token if genuinely missing.
   • `SupportingAISettingsView.swift` — fix the `.orange` usage so the `ShapeStyle`/`Color` types match (use `Color.orange` in the foreground-style context).
   • `SlashCommandRegistry.swift` — give the sort a concrete `KeyPathComparator`/typed closure instead of a bare `(_, _) -> Bool` where a `SortComparator` is expected.
   • `AppDelegate.swift:89` — `NSApp.replyToApplicationShouldTerminate(true)` → `NSApp.reply(toApplicationShouldTerminate: true)`.
   Why: These are independent API mismatches/renames; each blocks the build and must use the current framework spelling (SR-2 / SR-5).

- [ ] 5. **Production-polish the AI-detection heuristic (ISS-016 follow-up)**
   What: In `MainAIMonitor.processLine`, tighten the session-reset detection so it does not clear on any output line merely *containing* `clear`/`exit`/`newgrp`; key the Claude welcome-banner match off a stable substring rather than relying solely on the exact emoji. (Behavioural polish, no API change.)
   Why: Production quality — the current heuristic risks false clears from ordinary output; this is the Foundation-side counterpart to the Terminal polish plan.

- [ ] 6. **Fix the Swift-6 actor-isolation conformance + minor polish (ISS-027)**
   What: In `2 Foundation/2.7 Utilities/MainAIMonitor.swift`, declare `observe(line:)` `nonisolated` so the `TerminalAIOutputObserving` conformance no longer crosses the main-actor boundary (it only yields to a `Sendable` `AsyncStream` continuation). While here: drop the redundant `await` flagged at line 139, and add the MR-3 justification comment to the surviving `DispatchQueue.global` file-watcher at line 308 (DispatchSource has no async/await equivalent).
   Why: ISS-027 — the conformance "can cause data races" and is a hard error under the Swift 6 language mode (SW-1); the await/comment items are production hygiene that ride along for free.

- [ ] 7. **Wire the window title to the workspace folder (ISS-028)**
   What: In `App-Sputnik/ContentView.swift`, apply `.navigationTitle(windowState.title)` (and optionally `.navigationDocument(url)` when `activeWorkspaceDirectory` is set) to the window's root view, so the existing `WindowState.title` (folder name, or "Untitled") actually appears on the `NSWindow`. No change to `WindowState` itself — the computed property already exists.
   Why: ISS-028 — the title is computed but never bound, so every window shows SwiftUI's default title; binding it makes multi-window/Merge All Windows legible (SR-2: spec behaviour unmet).

- [ ] 8. **Route file-tree opens through `InterPanelRouter` (ISS-029) — MODULE 6 TOUCH**
   What: In `6 Project File Tree/FileTreeViewModel.swift:115`, replace the direct `windowState?.openDocument(url: id)` call with `await router.open(id)`. Inject the `InterPanelRouter` into `FileTreeViewModel` (constructor or `configure`) the same way other panels receive it; keep `windowState` only for non-document state. Verify the router's `open(_:)` still resolves to the correct per-window `WindowState`.
   Why: ISS-029 — `DocumentSession`'s contract says modules must create sessions only through the 2.1 router, never by touching `WindowState` directly; this restores the one-way cross-module boundary (SR-1).

- [ ] 9. **Build clean and sweep remaining errors**
   What: check the logic of `swift build` from the root; fix any residual errors surfaced once the big clusters clear (the per-file fan-out can mask a few). 
   Why: The 30-site count is from the first failing pass; clearing the leaders may reveal a small tail. Success is clean logic, not a lower error count.

## Risks and Constraints
- **Foundation blast radius:** every module depends on module 2 — verify dependent modules still build after the changes (Step 6 covers the executable target, which pulls them all).
- **Deletion safety (Step 2):** confirm no live code imports `ClaudeStatusLineReader`/`TerminalModelDetector` before deleting; if anything still references them, migrate the call site to `MainAIMonitor` rather than resurrecting the file.
- **Refactor fidelity:** these errors stem from a half-applied rename (ISS-015/016) — prefer completing that rename's intent over re-introducing the old `terminalModelInfo` API.
- No new force-unwraps, no `DispatchQueue` business logic, `@MainActor` on UI types (SR-2 / SW-1).
- **Module-6 deviation (Step 8):** this plan is otherwise Foundation-only, but routing the file-tree open through the 2.1 router requires one edit in module 6. It is a 1-line call-site change plus router injection — flagged here so the cross-module touch is explicit, not silent.

## Files Affected
- `2 Foundation/2.4 UI and UX/SputnikAlert.swift` — escape inner quotes.
- `2 Foundation/2.7 Utilities/ClaudeStatusLineReader.swift` — delete (orphan).
- `2 Foundation/2.7 Utilities/TerminalModelDetector.swift` — delete (orphan).
- `2 Foundation/2.7 Utilities/MainAIMonitor.swift` — fix `deinit` isolation; `nonisolated observe(line:)` (ISS-027); drop redundant `await`; MR-3 comment on file-watcher; tighten detection heuristic.
- `2 Foundation/2.3 Settings/SettingsStore.swift` — add `terminalFontName` (+ siblings) to `DefaultsKey`.
- `2 Foundation/2.4 UI and UX/DocumentTabBar.swift` — fix accent colour token.
- `2 Foundation/2.3 Settings/SupportingAISettingsView.swift` — fix `.orange` shape-style usage.
- `2 Foundation/2.7 Utilities/SlashCommandRegistry.swift` — typed `SortComparator`.
- `2 Foundation/2.6 App Lifecycle/AppDelegate.swift` — `reply(toApplicationShouldTerminate:)`.
- `App-Sputnik/ContentView.swift` — bind `navigationTitle` to `windowState.title` (ISS-028).
- `6 Project File Tree/FileTreeViewModel.swift` — open via `router.open(_:)` instead of `windowState.openDocument` (ISS-029); inject the router. **(module 6 touch)**
- Possibly a module `Package.swift` if it names a deleted file.

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (`swift build` from root = 0 errors)
- [ ] Module Guide(s) updated where behaviour changed (2.7 Utilities `last_updated`)
- [ ] Issues.md: mark ISS-023, ISS-024, ISS-025, ISS-026, ISS-027, ISS-028, ISS-029 Resolved with dated notes
- [ ] Changes committed: `[2 Foundation] Make the project compile`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
