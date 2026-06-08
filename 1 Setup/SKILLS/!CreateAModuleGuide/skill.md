# Skill: !CreateAModuleGuide

## Purpose
Scaffold a new Module Guide file in the correct location, populated with accurate content drawn from the project spec and any existing code.

---

## When to invoke
- User asks to create or add a module guide
- `!GenerateAPlan` determines a guide is missing before planning can proceed
- A new sub-module is being added to an existing module

---

## Inputs
The user must supply one of:
- A top-level module: e.g. `3 Editor Window`
- A sub-module: e.g. `2.1 Inter-panel communication`

If not supplied, ask before proceeding: *"Which module or sub-module should I create a guide for?"*

---

## Steps

### 1. Gather context
Run these reads in parallel:

- Read `readme.md` — extract TWO things:
  1. **App purpose** (top of file): the single sentence describing what Sputnik is and does — this is the alignment anchor used in Step 3
  2. **Module spec** (relevant numbered section): the bullet points for the target module/sub-module
- Read `1 Setup/Vibe_Coding_Rules.md` — note any rules that apply to this module
- Check `1 Setup/Module Guides/` — confirm no guide already exists for this target (if one does, ask the user whether to overwrite or update it)
- If Swift source files exist for this module, scan them for key types, protocols, and framework imports

### 2. Determine output path
| Target type | Output path |
|---|---|
| Top-level module (e.g. `3 Editor Window`) | `1 Setup/Module Guides/3 Editor Window/guide.md` |
| Sub-module (e.g. `2.1 Inter-panel communication`) | `1 Setup/Module Guides/2 Foundation/2.1 Inter-panel communication/guide.md` |

### 3. Check module purpose against app purpose
Before writing anything, draft a one-sentence Purpose statement for this module and check it against the app purpose extracted in Step 1.

Ask: **does this module's purpose directly serve Sputnik's stated reason for existing?**

A module purpose passes if it clearly contributes to one or more of Sputnik's core traits: modular, error-proof, fast, low-memory, Markdown/PDF reader, Finder-style file explorer, or Terminal interface.

| Result | Action |
|---|---|
| Passes | Proceed to Step 4 |
| Unclear fit | Stop — show the app purpose and the draft module purpose side by side, explain the gap, and ask the user to confirm or revise before continuing |
| Clear conflict | Stop — do not write the guide; report that the module as described does not serve the app's purpose and ask the user how to proceed |

### 4. Write the guide
Use the template at `1 Setup/References/module-template.md`. Fill every section — do not leave placeholders.

### 5. Confirm
Print the output path and a one-line summary of what was written. If any section required assumptions (e.g. no source code exists yet), flag those lines with `<!-- assumed -->`.

---

## Output Template

```markdown
---
module: <N.N Module Name>
status: draft
last_updated: <YYYY-MM-DD>
---

## Purpose
<One sentence: what this module does and why it exists in Sputnik.>

## Diagram
<ASCII art showing either:
  - UI layout: panels, labels, borders drawn with box-drawing chars
  - OR call/data flow: boxes connected with arrows showing how data moves>

## Technical Summary
- **Framework(s):** <e.g. PDFKit, SwiftUI, AppKit>
- **Key types:** <ClassName / StructName — one-liner on each>
- **Threading model:** <which work is on main thread vs background; what GCD queues or Tasks are used>
- **Data flow:** <how data enters, transforms, and exits this module>
- **State owned:** <what @State / @ObservableObject / actor this module controls>
- **Dependencies:** <which other modules or Foundation types this module calls into>
- **Failure modes:** <what can go wrong and how it is handled>

## Spec Reference
> Extracted from `readme.md` — the original bullet points for this module:
<paste the relevant lines verbatim>
```

---

## Rules
- `status` must be `draft` on creation. Only `!GenerateAPlan` promotes it to `active`.
- Do not invent API names. If source code does not exist yet, describe the *intended* design and mark with `<!-- assumed -->`.
- The Diagram must be ASCII only — no images, no Mermaid, no LaTeX.
- The Purpose statement is exactly one sentence.
- Spec Reference is always included verbatim so the guide stays traceable to the source spec.
