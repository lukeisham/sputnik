---
plan: Fix correctness and data-safety bugs
module: 6 Project File Tree
created: 2026-07-02
status: pending
related_issues: ISS-161, ISS-162, ISS-164, ISS-165, ISS-166, ISS-167
---

## Purpose
Fix six correctness bugs in the File Tree's refresh, drag-and-drop, and file-operation paths so the tree never silently mis-renders, mis-moves, or mis-targets a file operation.

## Success Condition
- Expand a folder, then trigger any refresh path (create a file, rename a file, drop a file, or touch a file from Terminal) — the folder stays expanded **and** its children remain visible without manual collapse/re-expand.
- Drag a file from a sibling directory whose name is a prefix of the active root's name (e.g. active root `.../Proj`, source file under `.../Project-Notes/`) into the tree — the file is **copied**, not moved; the original file still exists at the source path.
- Trigger a drop that fails (e.g. drop a folder into itself, or drop onto a name that already exists) — a `SputnikAlert` appears describing the failure instead of silently doing nothing.
- Batch-trash a multi-selection containing several permission-denied items — exactly one alert appears, listing all failures, not one modal per item.
- Rename an expanded folder — it stays expanded after the rename (no stale ID left behind, no unexpected collapse).
- Right-click a node that is *not* in the current selection while another node *is* selected, and choose "Move to Trash" — only the right-clicked node is trashed.
- `!CreateTests`-style unit tests (or manual verification against `Tests/FileTreeModuleTests.swift`) cover the new prefix-matching and refresh-preservation logic.

## Steps

- [ ] 1. **Preserve expanded subtrees across `refreshTree()`**
   What: In `FileTreeViewModel.refreshTree()`, after building the new root's single-level children, walk `expandedNodeIDs` and re-run `loadLevel` (or reuse the existing children already known to the previous tree) for every node ID that is both a directory and currently expanded, merging results back via the existing `applyChildren` helper — so previously-expanded folders come back populated instead of `nil`.
   Why: ISS-161 — every refresh currently blanks all expanded folders' contents even though the chevron still shows "expanded," directly contradicting the guide's documented behaviour.

- [ ] 2. **Fix intra-tree vs external drop classification**
   What: In `FileTreeViewModel.handleDrop`, replace `activeDirPath.map { url.path.hasPrefix($0) }` with a path-component-aware check (e.g. compare `url.pathComponents` against `activeDirectory.pathComponents` as a proper prefix, or use `hasPrefix(activeDirPath + "/")` guarding the exact-match case too).
   Why: ISS-162 — the current raw string-prefix check misclassifies sibling directories with overlapping name prefixes, causing an unintended **move** (source file deletion) instead of a copy.

- [ ] 3. **Surface drop failures via `SputnikAlert`**
   What: In the `catch` block of `FileTreeViewModel.handleDrop`'s `Task { @MainActor in ... }`, call the existing private `showAlert(title:message:)` helper with the error's `localizedDescription` instead of silently discarding it. Keep the "unsupported type" `guard provider.hasItemConformingToTypeIdentifier` path silent, since that's a legitimate system-level rejection, not a file-operation failure.
   Why: ISS-164 — the guide's failure-mode spec requires file-operation failures to surface an alert; drops currently violate that silently, leaving the user with no explanation for a failed drop.

- [ ] 4. **Aggregate batch-trash failures into one alert**
   What: In `FileTreeViewModel.trash(nodeIDs:)`, collect failed items' names and error messages into an array instead of calling `showAlert` inside the loop; after the loop, if the array is non-empty, call `showAlert` once with a combined message (e.g. one line per failed item).
   Why: ISS-165 — trashing a selection with multiple failures currently stacks that many sequential blocking `NSAlert.runModal()` calls, which is a poor and confusing UX for a single user action.

- [ ] 5. **Keep `expandedNodeIDs` in sync during rename**
   What: In `FileTreeViewModel.rename(nodeID:to:)`, mirror the existing `selectedNodeIDs` swap (remove old URL, insert new URL) for `expandedNodeIDs` as well, before calling `refreshTree()`.
   Why: ISS-166 — renaming an expanded folder currently leaves the old URL orphaned in `expandedNodeIDs` and the folder visually collapses even though the set still "thinks" it's expanded.

- [ ] 6. **Target the right-clicked node for "Move to Trash" when it's outside the selection**
   What: In `FileContextMenu`'s "Move to Trash" button action, trash `viewModel.selectedNodeIDs` only when `node.id` is a member of it; otherwise trash just `[node.id]` (matches the existing ternary pattern already used for the empty-selection case — extend the condition rather than replacing it).
   Why: ISS-167 — right-clicking an unselected node while a different node is selected currently trashes the wrong (selected) node, diverging from standard Finder behaviour and posing a real risk of accidental deletion.

- [ ] 7. **Add/extend unit tests**
   What: Add test cases to `6 Project File Tree/Tests/FileTreeModuleTests.swift` covering: (a) the corrected prefix-matching helper for intra-tree detection with a sibling-prefix directory name, (b) `expandedNodeIDs` surviving a `refreshTree()` call, (c) `expandedNodeIDs` migrating on rename. Extract the drop-path-classification logic into a small `nonisolated` static helper if needed to make it independently testable.
   Why: These are the highest-risk regressions (silent data movement, silent visual staleness) — regression coverage prevents them from resurfacing.

- [ ] 8. **Manual verification pass**
   What: Run the app, open a real folder with nested subdirectories, and manually walk through every scenario in the Success Condition section above.
   Why: Unit tests cover logic; the refresh/expand interaction and alert stacking are UI-observable behaviours best confirmed by hand per CLAUDE.md's "test the golden path" guidance.

## Risks and Constraints
- SR-1: stay within module 6; do not touch `InterPanelRouter` or `WindowState` beyond what's already wired.
- SR-2: no force-unwraps introduced; all new error paths must route through the existing `showAlert` helper.
- SW-1: all new/changed logic must stay on `@MainActor` or the existing `nonisolated static` boundary — do not introduce ad-hoc `DispatchQueue` calls.
- The `refreshTree()` fix (step 1) is the riskiest change — it must not reintroduce ISS-104 (accidentally scanning on the main thread) or cause redundant re-scans of every expanded folder on every keystroke-driven refresh; batch/parallelize the re-expansion if there are many expanded folders.

## Files Affected
- `6 Project File Tree/FileTreeViewModel.swift` — `refreshTree()`, `handleDrop`, `trash(nodeIDs:)`, `rename(nodeID:to:)`
- `6 Project File Tree/FileContextMenu.swift` — "Move to Trash" button action
- `6 Project File Tree/Tests/FileTreeModuleTests.swift` — new test cases

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[6 Project File Tree] Fix correctness and data-safety bugs`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
