---
plan: <short title>
module: <N Module Name>
created: <YYYY-MM-DD>
status: pending
related_issues: <ISS-NNN, … or none>
---

<!--
  HOW TO USE
  - Copy this file to: 1 Setup/Plans New/YYYY-MM-DD <Module> <short-title>.md
  - Fill every section before presenting the plan for approval
  - Do not start coding until the user replies "go"
  - Check off steps in this file as work progresses
  - Move to Plans Completed/ after the GitHub push

  REQUIRED READS BEFORE WRITING THIS PLAN:
  1. 1 Setup/Vibe_Coding_Rules.md
  2. Module Guide(s) for every affected module

  EDITING MARKDOWN FILES:
  - Claude: use built-in file editing tools
  - Any other agent: use Python to read and write .md files

    from pathlib import Path
    p = Path("path/to/file.md")
    p.write_text(p.read_text().replace(old, new))   # edit in place
    p.write_text(p.read_text() + new_content)        # append
-->

## Purpose
<One sentence: the single problem this plan solves or capability it adds. This is the north star — every step must serve it.>

## Success Condition
<How to verify the work is done — what to run, see, or test when complete.>

## Steps

- [ ] 1. **<Step title>**
   What: <what to do>
   Why: <why this step is needed>

- [ ] 2. **<Step title>**
   What: <what to do>
   Why: <why this step is needed>

- [ ] 3. **<Step title>**
   What: <what to do>
   Why: <why this step is needed>

<!-- Add steps as needed. Target 5–15. Every step needs both a What and a Why. -->

## Risks and Constraints
- <Anything that could go wrong, a Vibe Rule that limits the approach, or a module boundary to respect>

## Files Affected
- `path/to/file.swift` — <one-liner on what changes>

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (ran / tested / confirmed as described above)
- [ ] Module Guide(s) updated (`status` + `last_updated`)
- [ ] Changes committed: `[<Module>] <Plan title>`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
