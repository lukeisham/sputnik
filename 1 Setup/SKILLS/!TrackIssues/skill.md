# Skill: !TrackIssues

## Purpose
Log bugs, missing features, or Vibe Coding Guide violations found in the codebase to the central issue table at `1 Setup/References/Issues.md`.

---

## When to invoke
- You spot a bug while reading or editing code
- Code does not match the Vibe Coding Rules (force-unwrap, completion handler, third-party package, etc.)
- A spec feature is absent from the implementation
- `!GenerateAPlan` or `!GrillMeWithContext` surfaces a problem that is out of scope for the current task
- The user explicitly says to log an issue

---

## Inputs
Supply as many of the following as are known. Missing fields can be inferred from context or marked `unknown`.

| Field | Required | Notes |
|---|---|---|
| `module` | yes | e.g. `3 Editor Window` or `2.1 Inter-panel communication` |
| `type` | yes | `Bug` / `Missing Feature` / `Vibe Violation` |
| `description` | yes | One sentence — what is wrong or missing |
| `severity` | yes | `High` / `Medium` / `Low` (see definitions below) |
| `rule_violated` | if Vibe Violation | e.g. `Swift Rule 2` or `Sputnik Rule 3` |
| `file` | if known | Source file path and line number |

### Severity definitions
| Level | Meaning |
|---|---|
| **High** | Crash risk, data loss, or blocks core functionality |
| **Medium** | Feature is broken or spec requirement unmet, but app still runs |
| **Low** | Style, performance concern, or minor spec gap |

---

## Steps

### 1. Read the current issue table
Read `1 Setup/References/Issues.md` to get the last issue ID so the next ID increments correctly.

### 2. Read the Vibe Coding Rules (if type is Vibe Violation)
Read `1 Setup/Vibe_Coding_Rules.md` and confirm which rule number is violated. Fill `rule_violated` precisely (e.g. `Swift Rule 1 — async/await`).

### 3. Assign the next ID
Format: `ISS-NNN` (zero-padded to 3 digits). If the table is empty, start at `ISS-001`.

### 4. Append the row
Add one new row to the Markdown table in `Issues.md`. Do not reformat or reorder existing rows.

### 5. Confirm
Print the new issue ID and its one-line description. If the issue was found while doing something else, remind the user which task was in progress so they can resume it.

---

## Issues.md Row Format

Each row maps to these columns (in order):

```
| ID | Date | Module | Type | Description | Severity | Rule Violated | File | Status |
```

| Column | Format |
|---|---|
| ID | `ISS-NNN` |
| Date | `YYYY-MM-DD` |
| Module | Module number and name (e.g. `3 Editor Window`) |
| Type | `Bug` / `Missing Feature` / `Vibe Violation` |
| Description | One sentence, plain English |
| Severity | `High` / `Medium` / `Low` |
| Rule Violated | Vibe rule reference, or `—` if not applicable |
| File | `path/to/file.swift:line` or `—` if unknown |
| Status | Always `Open` on creation |

---

## Rules
- Never edit or delete existing rows — append only.
- One issue per row. If multiple problems are found, log each separately.
- Description must be a complete sentence that stands alone out of context.
- Status is always `Open` when logged. Only a developer (or `!GenerateAPlan`) changes it to `In Progress` or `Resolved`.
- If the same issue already exists in the table (same module + same description), do not duplicate — report the existing ID instead.
