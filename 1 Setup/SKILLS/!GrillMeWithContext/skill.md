# Skill: !GrillMeWithContext

## Purpose
Establish exactly what the user wants before any code is read, planned, or written. Ask one targeted question at a time until the intent is unambiguous, then route to the right skill or action.

---

## When to invoke
- The user's request is vague or could mean several different things
- You are unsure whether the user wants a plan, a fix, a refactor, or an explanation
- Start every new session here unless the intent is already crystal clear

---

## How it works
Ask **one question at a time**. Wait for the answer. Use it to narrow down intent before asking the next question. Stop asking as soon as you know enough to route confidently — do not ask questions you can already answer from context.

Maximum 4 questions before routing. If intent is still unclear after 4, make a reasonable assumption, state it explicitly, and proceed.

---

## Question sequence

Work through these topics in order, stopping as soon as intent is clear:

### Q1 — What kind of task is this?
> "Is this a bug fix, a new feature, a refactor, or do you need an explanation of something?"

| Answer | Next step |
|---|---|
| Bug fix | Ask Q2 (scope), then route → **Fix flow** |
| New feature | Ask Q2 (scope), then route → **`!GenerateAPlan`** |
| Refactor | Ask Q2 (scope), then route → **Refactor flow** |
| Explanation | Ask Q3 (topic), then answer directly — no plan needed |
| Unsure / mixed | Ask Q2 to narrow down |

### Q2 — Which module or file?
> "Which module is this in — or do you have a specific file in mind?"

Use the answer to read the relevant Module Guide before proceeding. If no guide exists, note that and suggest running `!CreateAModuleGuide` first.

### Q3 — What is the current behaviour vs the desired behaviour? (bugs and features only)
> "What is it doing now, and what should it do instead?"

This establishes the success condition. Skip for explanations and pure refactors.

### Q4 — Any constraints I should know about? (optional)
> "Any constraints — timing, specific files to avoid, related issues already logged?"

Check `1 Setup/References/Issues.md` for related open issues before asking this — if one exists, surface it and ask if it's connected.

---

## Routing

| Intent confirmed | Route to |
|---|---|
| Bug — single module, isolated | Log with `!TrackIssues` → fix inline |
| Bug — multi-module or architectural | Log with `!TrackIssues` → `!GenerateAPlan` |
| New feature | `!GenerateAPlan` |
| Refactor | Read Module Guide → refactor inline if small; `!GenerateAPlan` if it spans multiple files |
| Explanation | Answer directly using Module Guide + spec as sources |
| Missing Module Guide | `!CreateAModuleGuide` first, then re-route |

---

## Rules
- Never ask a question you can already answer from the conversation or by reading a file.
- Never ask two questions at once.
- Always read the relevant Module Guide before routing — it may change the answer.
- State your routing decision out loud before acting: *"This looks like a bug in module 6. I'll log it with !TrackIssues and then fix it inline."*
