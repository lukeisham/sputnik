---
plan: Scope keyboard shortcuts and harden watcher lifecycle
module: 6 Project File Tree
created: 2026-07-02
status: pending
related_issues: ISS-163, ISS-168, ISS-169
---

## Purpose
Scope the File Tree's hidden keyboard-shortcut buttons to only fire when the tree actually has focus, and remove the false safety claim (and associated crash risk) in `FileSystemWatcher`'s C-callback lifetime handling.

## Success Condition
- With the editor or terminal focused, pressing ⌘N, ⌘⇧N, Return, ⌘C, or Space does **not** trigger any File Tree action (new file, rename, copy-path, Quick Look) — those keys behave as the focused panel expects, and the main menu's own ⌘N/⌘C bindings work normally.
- With the File Tree panel focused (a row selected / the tree itself is `@FocusState`-focused), the same shortcuts continue to work exactly as before.
- `FileSystemWatcher`'s callback-vs-deinit race is closed: the watcher either keeps itself alive for the duration of any in-flight callback, or the doc comment is corrected to describe the actual (verified) guarantee — whichever the implementation review determines is correct — with no behavioural regression to ISS-114/ISS-115's existing fixes.
- `1 Setup/Module Guides/6 Project File Tree/guide.md` no longer describes the removed "⌘⌫ button" (it should describe `.onDeleteCommand` instead), no longer claims chunked "Loading more…" behaviour that isn't implemented, and no longer lists `SputnikShared` as a package dependency.

## Steps

- [ ] 1. **Add a focus scope to the File Tree panel**
   What: Introduce a `@FocusState` (or reuse an existing Foundation 2.4 focus-routing primitive if one already exists for other panels — check `HelpTopic.swift`/focus-navigation code from ISS-140's "Focus Navigation" menu items first) on `FileTreePanel`, bound to the tree's `ScrollView`/`List` container.
   Why: ISS-163 — the hidden shortcut buttons currently have no way to know whether the tree is the intended target of a keypress; a focus scope is the prerequisite for gating them.

- [ ] 2. **Gate `keyboardShortcutOverlay` and `quickLookShortcut` on focus**
   What: Wrap the hidden-button `Group`s (or each button individually) so their actions early-return (or the buttons are conditionally not rendered / `.disabled(!isTreeFocused)`) when the new focus state is `false`.
   Why: ISS-163 — this is the actual fix: ⌘N/⌘⇧N/Return/⌘C/Space must not fire File Tree actions while another panel has focus.

- [ ] 3. **Verify interaction with the app's existing Focus Navigation shortcuts**
   What: Confirm `⌃⌘F` ("Focus: File Tree", referenced in ISS-140's guide-drift note) actually sets the new focus state so keyboard users can reach the tree and have its shortcuts activate; test the full focus cycle (`⌃⇥`/`⌃⇧⇥`) still moves focus in and out correctly.
   Why: The fix must not trap keyboard-only users out of the File Tree's shortcuts — focus scoping has to compose with the app's existing focus-navigation system, not fight it.

- [ ] 4. **Audit and fix (or correctly document) the `FileSystemWatcher` deinit race**
   What: In `FileSystemWatcher`, either (a) make the watcher retain itself for the FSEventStream's lifetime independent of external strong references (e.g. hold a self-reference released only inside `stop()`, so `deinit` cannot run while a callback could still be scheduled), or (b) if analysis confirms `FSEventStreamSetDispatchQueue` + `FSEventStreamInvalidate` already guarantee no callback survives invalidation on the watch queue, correct the misleading comment at `FileSystemWatcher.swift:90-100` to state that guarantee precisely instead of the current inaccurate claim. Pick (a) if there's any real reachable path where the last strong reference can drop before `stop()` is explicitly called (e.g. `FileTreeViewModel.startWatching` replacing `watcher` without calling old `.stop()` first — check this).
   Why: ISS-168 — the existing doc comment asserts a safety guarantee the code doesn't structurally provide; either close the gap or make the comment honest, since SW-4 requires documentation to match actual behaviour and SR-2 requires the app to be crash-proof.

- [ ] 5. **Update `guide.md` to remove drift**
   What: In `1 Setup/Module Guides/6 Project File Tree/guide.md`: replace the "⌘⌫" hidden-button line in the Keyboard Shortcuts section with a note that trash is bound via `.onDeleteCommand`; remove or caveat the "Extremely large directory... chunked... Loading more…" failure-mode bullet since it is not implemented (either mark it as a known gap or delete the claim); correct the dependency line to drop `SputnikShared` as a separate package (confirm `DebounceTimer`'s actual module/import before editing).
   Why: ISS-169 — the guide is the source of truth per CLAUDE.md's "Read the Module Guide before touching a module" convention; leaving it stale misleads the next person to touch this module.

- [ ] 6. **Manual and automated verification**
   What: Manually test the focus-scoping success conditions above in the running app; if `FileSystemWatcher` gained new logic in step 4, add a test to `Tests/FileTreeModuleTests.swift` exercising `stop()` racing a simulated callback (or, if only the comment changed, no new test is required — note that in the closeout).
   Why: Confirms the fix works end-to-end and that the shortcut scoping doesn't silently break the un-focused case for other panels.

## Risks and Constraints
- SW-3: focus state belongs in SwiftUI (`@FocusState`), not a manual AppKit responder-chain hack, unless investigation in step 1 shows Foundation already has a focus-routing primitive that should be reused instead (SR-1: don't duplicate cross-module UI infrastructure).
- Do not regress ISS-114/ISS-115's existing fixes (root-loss sentinel, `NSLock`-guarded `continuation`) while touching `FileSystemWatcher` in step 4.
- Keep this plan scoped to module 6; if step 3 reveals the app-wide Focus Navigation system itself needs changes, that's a Foundation (module 2) change and must be split into its own plan per CLAUDE.md's "Foundation changes affect every other module" flag.

## Files Affected
- `6 Project File Tree/FileTreePanel.swift` — `keyboardShortcutOverlay`, `quickLookShortcut`, new focus state
- `6 Project File Tree/FileSystemWatcher.swift` — lifetime/self-retain handling or corrected doc comment
- `1 Setup/Module Guides/6 Project File Tree/guide.md` — drift corrections
- `6 Project File Tree/Tests/FileTreeModuleTests.swift` — new test(s) if step 4 changes behaviour

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[6 Project File Tree] Scope keyboard shortcuts and harden watcher lifecycle`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
