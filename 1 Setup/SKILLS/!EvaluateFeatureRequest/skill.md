# Skill: !EvaluateFeatureRequest

## Purpose
Assess whether a requested feature fits the existing architecture, which modules it would touch, what scope it would require, and whether it conflicts with open plans or issues — before any implementation planning begins.

---

## When to invoke
- A new feature is requested and its architectural fit is unclear
- `!GrillMeWithContext` routes here because the request is feature-shaped but may conflict with existing work or strain the module boundaries
- A feature request arrives from outside the dev team (e.g. user report, App Store review, stakeholder ask)
- The request spans more than one module and it is unclear where ownership should sit

---

## Inputs

| Input | Required | Notes |
|---|---|---|
| Feature description | yes | What the user wants — as specific as possible |
| Motivation | if known | Why they want it — affects how to scope it |
| Module | if known | Where the user expects it to live |

If only a vague description is provided, ask one clarifying question before proceeding: *"What problem would this solve — or what would the user be able to do that they cannot do now?"*

---

## Steps

### 1. Read open work
Run these reads in parallel:
- `1 Setup/References/Issues.md` — look for open issues the feature would resolve or conflict with
- `1 Setup/Plans New/` — list any in-progress plans that touch the same modules

Note any matches. A feature that duplicates an open plan or resolves an open issue changes the scope of work.

### 2. Read the Module Guide(s)
Read the Module Guide for every module the feature is likely to touch. Identify:
- Which module owns the data or behaviour the feature needs
- Whether the feature requires a new type or protocol in Foundation (module 2), or can be contained within a single module
- Any documented constraints, design decisions, or explicit non-goals that would block this feature

If no guide exists for the affected module, note it — the guide must be created before a plan can be written.

### 3. Read the Vibe Coding Rules
Read `1 Setup/Vibe_Coding_Rules.md`. Identify any rules the feature would strain:
- SR-1: Does it require a shared type or setting? If so, it must go through Foundation.
- SR-3: Does it load or hold data in memory at scale? Check for RAM implications.
- SR-4: Does it involve file I/O, shell, or heavy computation? Must stay off the main thread.
- SR-5: Does it need a third-party dependency? If yes, flag as a blocker.

### 4. Produce the evaluation

Write a structured evaluation with the following sections:

#### Feature Summary
One sentence restating the request in implementation terms.

#### Module Impact
List every module that would change and what role it plays:

| Module | Change type | Notes |
|---|---|---|
| e.g. `3 Text Editor` | New UI control | Adds a toolbar button |
| e.g. `2 Foundation` | New shared type | `WritingMode` enum added to SettingsStore |

#### Foundation Impact
State explicitly whether module 2 (Foundation) would need to change. Foundation changes affect every other module — flag this prominently if yes.

#### Scope Estimate
| Size | Meaning |
|---|---|
| **Small** | One module, ≤ 3 files, no Foundation changes |
| **Medium** | One or two modules, ≤ 8 files, minor Foundation change (new field or case) |
| **Large** | Three or more modules, or a structural Foundation change (new type, new protocol, new lifecycle hook) |

#### Conflicts
List any open issues or in-progress plans that overlap. State whether this feature resolves, extends, or blocks them.

#### Vibe Rules at Risk
List any Sputnik or Swift rules the feature would strain, with a brief explanation. If none, write "None identified."

#### Recommendation
One of three outcomes:

| Outcome | Meaning |
|---|---|
| **Proceed** | Feature fits the architecture, no conflicts, scope is understood — route to `!GenerateAPlan` |
| **Proceed with conditions** | Feature fits, but a condition must be met first (e.g. a Module Guide must be created, an open issue must be resolved, or a Foundation change must be scoped separately) — state the condition |
| **Do not proceed** | Feature conflicts with a Vibe Rule, duplicates open work, or the scope cannot be bounded without an architectural change — explain why and suggest an alternative if one exists |

### 5. Route
| Recommendation | Next step |
|---|---|
| Proceed | Route to `!GenerateAPlan` with the evaluation as context |
| Proceed with conditions | Complete the stated condition, then re-evaluate or route to `!GenerateAPlan` |
| Do not proceed | Present the evaluation to the user; do not proceed to planning |

State the routing decision out loud before acting.

---

## Rules
- Never start a plan before evaluation is complete. The evaluation is the gate.
- If the feature description is ambiguous enough that the module impact cannot be determined, ask one clarifying question before reading any code.
- A "Do not proceed" is not a rejection — it is a scoped explanation. Always state what would need to change for the feature to become viable.
- If the evaluation reveals a new open issue (a missing type, an undocumented constraint, a gap in a Module Guide), log it with `!TrackIssues` before continuing.
- Foundation changes are never small. If module 2 needs to change, the scope estimate is at least **Medium**.
