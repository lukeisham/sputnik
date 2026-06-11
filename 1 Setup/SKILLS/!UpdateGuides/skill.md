# Skill: !UpdateGuides

## Purpose
Verify one Module Guide against the actual source code and update it to reflect current reality, so the guide prevents drift rather than causing it.

---

## When to invoke
- After a plan is completed and moved to `Plans Completed/`
- When a module guide contains `<!-- assumed -->` comments or stale frontmatter
- After a refactor or bug fix that touched module internals
- When `!DiagnoseABug` finds a discrepancy between the guide and the code
- Periodically as a maintenance pass — invoke as `!UpdateGuides: <module-name>`

---

## Inputs

| Input | Required | Notes |
|---|---|---|
| Module number or name | yes | e.g. `4`, `7 Terminal`, `2.3 Settings` |
| `all` | optional | Sweeps all guides in order; more time-consuming |

---

## Steps

### 1. Read the current guide
Read the full guide for the target module before touching any source files. Note:
- Any `<!-- assumed -->` or `[UNBUILT]` or `[UNVERIFIED]` markers
- The `status`, `last_updated`, and `last_verified` frontmatter fields
- Key types and file names mentioned in the Technical Summary
- Any Invariants section (or its absence)

### 2. List actual source files
Run `ls` on the module's source directory (e.g. `4 Markdown Preview/`). Build a file list.
Compare against what the guide names:
- Source files that exist but the guide does not mention → guide has a coverage gap
- Key types named in the guide that can't be found by `grep` → type may have been renamed or removed

### 3. Read the key source files
Read the files that own the core responsibilities — the main ViewModel, the primary View, any actor or coordinator. Do not read every file; focus on what the guide's Technical Summary describes.

Cross-check each guide section against what you actually see:

| Guide section | What to verify |
|---|---|
| **Key types** | Type names, responsibilities, and ownership still match |
| **Threading model** | `@MainActor`, actor isolation, background Task patterns still accurate |
| **Data flow** | Sequence of events still matches the diagram and bullet list |
| **Dependencies** | Imports and cross-module references still match the listed deps |
| **Failure modes** | Guard/catch paths still present in the code |
| **Invariants** | Each stated rule still holds — verify by reading, not by assumption |

### 4. Log discrepancies first
Any mismatch between guide and code → log it with `!TrackIssues` **before** editing the guide.

Do not silently update the guide to match broken code. The issue log is how problems get fixed; a quietly-updated guide hides them.

### 5. Update the guide
Apply the following updates:

**Frontmatter**
- Update `last_updated` to today's date
- Add (or update) `last_verified: YYYY-MM-DD` — distinct from `last_updated`; this is when someone last read the guide against real source
- Update `status` using this vocabulary:
  - `stable` — guide matches source; no known drift
  - `active` — module is under active development; guide may lag briefly
  - `needs-review` — guide has not been verified since a significant change
  - `diverged` — known gap between guide and code; logged in Issues
- Fix the `plan:` path if it still points to `Plans New/` for a completed plan

**Key types**
- Remove all `<!-- all assumed — no source code exists yet -->` comments
- Replace with verified type names, file locations (e.g. `MarkdownPreviewViewModel.swift`), and accurate one-line descriptions
- Mark anything genuinely unbuilt as `[UNBUILT]` (not `<!-- assumed -->`)
- Mark anything you couldn't confirm as `[UNVERIFIED — check source]`

**Source Files section** (add if absent)
Add a `## Source Files` section with a table of every `.swift` file in the module directory:

```markdown
## Source Files
| File | Responsibility |
|---|---|
| `FileName.swift` | One-line description of what this file owns |
```

**Invariants section** (add if absent)
Add a `## Invariants` section with the rules that must never be violated in this module. Rules should be specific and falsifiable — a future agent touching the module can read each one and check whether their change would violate it.

```markdown
## Invariants
- This panel **observes** AppState — it never writes to it (SR-1)
- All PTY I/O flows through `TerminalSession` actor — no direct `FileHandle.write` elsewhere
- `InterPanelRouter.open(_:)` is the only cross-module file-open path (SR-1)
- `NSTextView` is only touched on `@MainActor` (SW-1)
```

### 6. Final check
After editing, re-read the updated guide from top to bottom. Ask:
- Does every type name in the guide exist in source?
- Does the diagram still match the actual call flow?
- Are there any `<!-- assumed -->` or TODOs left?
- Does the Invariants list cover the things most likely to be broken by a careless change?

---

## Rules
- **Read source before writing guide.** A guide updated from memory is worse than a stale one.
- **Discrepancies go to Issues first.** Do not silently reconcile guide to broken code.
- **One module at a time.** Sweeping all guides in one pass risks compounding errors across modules.
- **`[UNBUILT]` beats `<!-- assumed -->`.** One is honest about missing implementation; the other looks like a draft note left by mistake.
- **Invariants must be falsifiable.** "This module is well-designed" is not an invariant. "This module never imports module 7 directly" is.
