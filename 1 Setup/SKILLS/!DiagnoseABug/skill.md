# Skill: !DiagnoseABug

## Purpose
Systematically investigate a reported bug — reproduce it, trace the failure path through code, and identify the root cause — before any fix is planned or written.

---

## When to invoke
- A bug is reported but its root cause is unclear (symptom known, cause unknown)
- `!GrillMeWithContext` routes here because the reported behaviour could have more than one cause
- A bug arrived as a user report rather than being found while reading code
- A previous fix did not hold and the failure is recurring

---

## Inputs
Supply as many of the following as are known. Missing fields can be inferred or asked for.

| Input | Required | Notes |
|---|---|---|
| Symptom | yes | What the user sees — exact behaviour, error message, or crash |
| Module | if known | Which module or view the symptom appears in |
| Reproduction steps | if known | What the user did immediately before the failure |
| Frequency | if known | Always / sometimes / once — affects where to look |

If the symptom alone is provided, that is enough to begin.

---

## Steps

### 1. Check the issue table
Read `1 Setup/References/Issues.md`. Search for matching symptoms in the same module.
- If a matching open issue already exists, report its ID, summarise what is already known, and ask the user whether to continue investigating or route directly to `!GenerateAPlan`.
- If a matching resolved issue exists, note it — the bug may have regressed.

### 2. Read the Module Guide
Read the Module Guide for every module the symptom could involve. Identify:
- The expected call flow for the reported action
- Which classes or functions own the failing responsibility
- Any known constraints or edge cases documented in the guide

If no guide exists for the affected module, stop and run `!CreateAModuleGuide` first.

### 3. Read the source
Read the source files identified in step 2. Trace the execution path from the action that triggers the symptom to the point where behaviour diverges from the spec. Look for:

| Category | What to check |
|---|---|
| Force-unwraps | Crash risk on unexpected nil |
| Threading | UI updates off `@MainActor`; shared state mutated from multiple threads |
| State ownership | Value written in the wrong module, bypassing Foundation |
| Lifecycle | Object released too early; observer not removed |
| Async gaps | `await` suspension point where state could change underneath |
| Framework misuse | API called incorrectly per Apple docs or Module Guide notes |

### 4. Form a hypothesis
State the suspected root cause in one sentence. Name the specific file and line number where the failure originates if possible.

Example: *"The crash occurs because `TerminalManager.currentSession` is force-unwrapped at `TerminalManager.swift:84` before the session is confirmed started."*

### 5. Verify the hypothesis
Confirm the hypothesis by reading the code path a second time with the root cause in mind. Check whether the same defect could manifest in other call sites. If the hypothesis does not hold up, return to step 3 with a revised theory.

### 6. Log the issue
Invoke `!TrackIssues` with the confirmed root cause as the description, the exact file and line, and the appropriate severity. Use the confirmed cause — not the symptom — as the description.

### 7. Route
| Root cause complexity | Next step |
|---|---|
| Single file, isolated, < 10 lines to fix | Fix inline; confirm with user first |
| Multi-file or touches a module boundary | Route to `!GenerateAPlan` with the diagnosis as context |
| Requires architectural change | Route to `!EvaluateFeatureRequest` to scope the change before planning |

State the routing decision out loud before acting.

---

## Rules
- Never write a fix before the root cause is confirmed. A fix aimed at the symptom without a confirmed cause is a guess.
- If two plausible hypotheses exist, state both and explain which is more likely before verifying.
- The issue logged in step 6 must describe the root cause, not just the symptom. *"App crashes when opening a file"* is a symptom. *"`FileLoader.load()` force-unwraps the bookmark data before checking `startAccessingSecurityScopedResource`'s return value"* is a root cause.
- If reading reveals a separate bug unrelated to the current diagnosis, log it with `!TrackIssues` and continue — do not context-switch.
