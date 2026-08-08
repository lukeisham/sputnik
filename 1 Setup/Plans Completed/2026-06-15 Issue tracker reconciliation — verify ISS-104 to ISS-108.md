---
plan: Issue tracker reconciliation — verify and close ISS-104 … ISS-108
module: Cross-module (5 PDF Viewer, 6 Project File Tree, 7 Terminal, 2.6 App Lifecycle)
created: 2026-06-15
status: pending
related_issues: ISS-104, ISS-105, ISS-106, ISS-107, ISS-108 (ISS-077 deferred)
---

> **Why this plan exists.** A read-through of the five remaining `Open` issues found that
> the code for **all five is already implemented** — only the `Status` column in
> `Issues.md` is stale (the fixes landed in earlier commits but their tracker rows were
> never flipped to `Resolved`). This plan does **not** write feature code. It *verifies*
> each fix against its original Success Condition and then *reconciles* the tracker. If any
> verification fails, that issue is split back out into its own implementation plan rather
> than being closed.

## Purpose
Bring `Issues.md` back into agreement with the source tree by verifying the already-landed
fixes for ISS-104 through ISS-108 and marking each `Resolved` (or re-opening it with a
dedicated plan if verification fails).

## Success Condition
- `swift build` is clean (already confirmed green this session).
- Each of the five issues is confirmed against its original fix description (evidence below).
- `Issues.md` shows ISS-104, ISS-105, ISS-106, ISS-107, ISS-108 as `Resolved — 2026-06-15`
  with a one-line evidence note citing the file:line that satisfies the fix.
- ISS-077 remains `Open` (deferred to its own future plan).
- Affected module guides (5, 6, 7, 2.6) state the off-main / cache / lazy-launch behaviour
  as current reality, with `last_verified: 2026-06-15`.

## Steps

- [ ] 1. **Verify ISS-104 (File Tree off-main scan)**
   What: Confirm `FileTreeViewModel.expandNode` uses `Task.detached(priority: .background)`
   ([line 107](6 Project File Tree/FileTreeViewModel.swift:107)) and `scanLevel` uses
   `Task.detached(priority: .userInitiated)` ([line 276](6 Project File Tree/FileTreeViewModel.swift:276)),
   both calling the `nonisolated static loadLevel`. Confirm `loadLevel` never captures `self`.
   Why: ISS-104's fix is "run `loadLevel` on the cooperative pool, not the main actor"; the
   `nonisolated static` + `Task.detached` pair is exactly that — verify before closing.

- [ ] 2. **Verify ISS-105 (PDF thumbnail off-main)**
   What: Confirm `PDFViewerViewModel.generateThumbnail` snapshots `capturedPage`/`cache`,
   runs `page.thumbnail(...)` inside `Task.detached(priority: .background)`, and writes the
   result back via `await MainActor.run` ([lines 277-285](5 PDF viewer/PDFViewerViewModel.swift:277)).
   Why: ISS-105's fix is "rasterise off the main actor with a snapshotted page" — confirm
   the detached block and the snapshot are both present.

- [ ] 3. **Verify ISS-106 (PDF thumbnail cache eviction)**
   What: Confirm `thumbnailCache` is `NSCache<NSNumber, NSImage>` ([line 69](5 PDF viewer/PDFViewerViewModel.swift:69))
   with `countLimit = 200` set in `init` ([line 85](5 PDF viewer/PDFViewerViewModel.swift:85)),
   and that load/close paths call `removeAllObjects()`.
   Why: ISS-106's fix is "bounded `NSCache` so bitmaps reclaim under pressure" — confirm the
   type and the count cap.

- [ ] 4. **Verify ISS-107 (lazy terminal PTY spawn)**
   What: Confirm `TerminalView.onAppear` early-returns unless `windowState.layout.terminalVisible`
   and `!hasLaunched` ([line 78](7 Terminal/TerminalView.swift:78)), and that the
   `onChange(of: terminalVisible)` first-reveal path spawns the tab on first show
   ([lines 82-89](7 Terminal/TerminalView.swift:82)).
   Why: ISS-107's fix is "defer `forkpty` off the launch path until the strip is visible" —
   confirm both the deferral guard and the first-reveal trigger exist.

- [ ] 5. **Verify ISS-108 (non-blocking crash-recovery alert)**
   What: Confirm `AppDelegate.applicationDidFinishLaunching` sets `appState?.pendingRecoveryNames`
   instead of looping `NSAlert.runModal()` ([lines 68-71](2 Foundation/2.6 App Lifecycle/AppDelegate.swift:68)),
   and that the consumer is a single SwiftUI `.alert` over the joined names
   ([ContentView:261-270](App-Sputnik/ContentView.swift:261)).
   Why: ISS-108's fix is "one consolidated, non-blocking notification" — confirm the blocking
   per-file modal loop is gone and a single alert renders all names.

- [ ] 6. **Run the build as the umbrella check**
   What: `swift build` from the repo root; expect "Build complete" with no errors.
   Why: A clean build proves all five verified call-sites compile together under strict
   concurrency — the cheapest single signal that the reconciliation is safe to commit.

- [ ] 7. **Reconcile Issues.md**
   What: For ISS-104, 105, 106, 107, 108 change `Status` from `Open` to
   `Resolved — 2026-06-15: <one-line evidence with file:line>`. Leave ISS-077 `Open`.
   Why: The tracker is the project's source of truth for issue state; stale `Open` rows for
   shipped fixes hide the real backlog (which is just ISS-077).

- [ ] 8. **Refresh the four affected module guides**
   What: In the guides for modules 5, 6, 7, and 2.6, confirm the off-main / `NSCache` /
   lazy-launch / non-blocking-recovery behaviour is described as current, and set
   `last_verified: 2026-06-15` (and `last_updated` where wording changes).
   Why: Guides are the design source of truth; they must not lag the verified code.

## Risks and Constraints
- **A verification might fail.** If any step 1-5 reveals the fix is partial (e.g. a snapshot
  missing, a guard that doesn't cover a path), do **not** mark that issue Resolved — split it
  into its own implementation plan in `Plans New/` and note it here.
- **No feature code.** This plan only edits `Issues.md` and module-guide `.md` files. If it
  starts touching `.swift` source beyond a one-line correction, scope has changed → new plan.
- **ISS-077 stays open.** The ZDOTDIR shim is genuinely unimplemented and was deferred; it
  needs its own dedicated, testable plan (shadowing `.zshenv`/`.zprofile`/`.zshrc`/`.zlogin`
  and surviving a user `.zshenv` that resets `ZDOTDIR`).
- **Append-only tracker.** `Issues.md` rows are append-only except the `Status` field — only
  the status cells of the five rows change.

## Files Affected
- `1 Setup/References/Issues.md` — flip ISS-104…108 `Status` to `Resolved` with evidence
- `1 Setup/Module Guides/5 PDF Viewer/guide.md` — confirm off-main thumbnails + NSCache; bump `last_verified`
- `1 Setup/Module Guides/6 Project File Tree/guide.md` — confirm off-main scan; bump `last_verified`
- `1 Setup/Module Guides/7 Terminal/guide.md` — confirm lazy PTY spawn; bump `last_verified`
- `1 Setup/Module Guides/2 Foundation/2.6 App Lifecycle/guide.md` — confirm non-blocking recovery; bump `last_verified`

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (build green; five issues confirmed against fix descriptions)
- [ ] Module Guide(s) updated (`last_verified` + any `last_updated`)
- [ ] Changes committed: `[Tracker] Reconcile ISS-104…108 — verify already-landed fixes`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
