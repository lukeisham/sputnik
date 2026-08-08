# Skill: !GenerateAPlan

## Purpose
Produce a clear, numbered implementation plan for a feature or fix, grounded in the Module Guide and Vibe Coding Rules, then stop and wait for approval before any code is written.

---

## When to invoke
- `!GrillMeWithContext` routes here after confirming intent
- The user explicitly asks for a plan
- A task spans more than one file or touches a module boundary

---

## Inputs
Before starting, confirm these are known (ask if not):

| Input | Source |
|---|---|
| Target module(s) | From `!GrillMeWithContext` or user |
| What to build or fix | From `!GrillMeWithContext` or user |
| Success condition | What "done" looks like |

---

## Steps

### 1. Read context — REQUIRED BEFORE ANYTHING ELSE
Do not write a single line of plan or code until these reads are complete.

Run in parallel:
- **`1 Setup/Vibe_Coding_Rules.md`** — internalize every rule; the plan must not propose anything that violates them
- **Module Guide(s) for every affected module** — the guide is the source of truth for that module's design intent; if no guide exists, stop and run `!CreateAModuleGuide` first
- `1 Setup/References/Issues.md` — surface any open issues in the affected modules
- Relevant source files (if they exist)

If either `Vibe_Coding_Rules.md` or a required Module Guide cannot be read, stop and report why before continuing.

### 2. Identify issues
While reading, flag anything that violates the Vibe Coding Rules or conflicts with the spec.
- For each issue found: invoke `!TrackIssues` to log it before continuing.
- Note the issue ID(s) in the plan so they are traceable.

### 3. Update the Module Guide (if needed)
If reading reveals the Module Guide is stale or missing information relevant to this plan, update it now. Mark changed sections with `last_updated: <today's date>`.

### 4. Write and save the plan
Use the template at `1 Setup/References/plan-template.md`. Save the file to:

```
1 Setup/Plans New/YYYY-MM-DD <Module> <short-title>.md
```

Example: `2026-06-07 3 Editor Window Add auto-save.md`

**New plans always go to `Plans New/` first. Never save directly to `Plans Completed/`.**

### 5. Present and stop
Print the plan in full. Then stop and say:
> "Plan saved to Plans New/. Reply **go** to start, or tell me what to change."

Do not write any code until the user approves.

### 6. On approval — execute and close
Work through each step in order. Check off steps as they complete (update the plan file).

When all implementation steps are done, run this closeout sequence in order:

1. Update any affected Module Guide's `status` field and `last_updated` date
2. Stage only the files changed by this plan — no unrelated files
3. Commit with the message format: `[<Module>] <Plan title>` (e.g. `[3 Editor Window] Add auto-save`)
4. Push to GitHub
5. **Move the plan file from `Plans New/` → `Plans Completed/`** — this is the final act; a plan not yet moved is not yet done
6. Report: plan title, files changed, commit hash, push result, and confirm the plan file location

---

## Plan File Format

```markdown
---
plan: <short title>
module: <N Module Name>
created: <YYYY-MM-DD>
status: pending
related_issues: <ISS-NNN, … or none>
---

## Purpose
<One sentence: the single problem this plan solves or capability it adds. This is the north star — every step must serve it.>

## Success Condition
<How to verify the work is done correctly — what to run, see, or test.>

## Steps

1. **<Step title>**
   What: <what to do>
   Why: <why this step is needed>
   
2. **<Step title>**
   What: <what to do>
   Why: <why this step is needed>

… (5–15 steps)

## Risks and Constraints
- <Anything that could go wrong or a rule that limits the approach>

## Files Affected
- `path/to/file.swift` — <one-liner on what changes>

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[<Module>] <Plan title>`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
```

---

## Rules
- Plan before code — never skip to implementation.
- Every step must have both a *what* and a *why*. A step without a *why* is not a step, it's a task list.
- If a plan requires touching Foundation (module 2), flag it explicitly — Foundation changes affect every other module.
- Plans are immutable once approved. If scope changes, create a new plan rather than silently editing the approved one.
- The plan file is the source of truth during execution. Update step checkboxes in the file as work progresses.
- **New plans are always saved to `Plans New/`.** Never save a new plan anywhere else.
- **A plan is not complete until it has been moved to `Plans Completed/`.** Moving the file is the closing action — do not report "done" before this step.
- **Editing `.md` files — if you are not Claude, use Python:**
  ```python
  from pathlib import Path
  p = Path("path/to/file.md")
  p.write_text(p.read_text().replace(old, new))  # edit in place
  p.write_text(p.read_text() + new_content)       # append
  ```
  Claude may use its built-in file editing tools. All other agents must use Python.
