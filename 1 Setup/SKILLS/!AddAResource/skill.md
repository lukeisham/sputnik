# Skill: !AddAResource

## Purpose
Add a new **hardcoded, built-in resource module** (a help category like JSON Help or Grammar Help) to module 9, wired into the Help menu, the writing-assist toggles, and — optionally — the special-elements registry. This is the dev-time path: resources are authored in-repo and shipped by rebuilding. It is **not** runtime/user extensibility (that was evaluated and declined — see note below).

---

## When to invoke
- You (the developer) want to add another help category to Sputnik at dev time.
- Invoke as `!AddAResource: <Resource Name>` (e.g. `!AddAResource: Chemistry`).

**Do not** invoke this to build user-upload / drag-and-drop extensibility. That requires converting the closed `HelpTopic` / `WritingAssistLanguage` enums to a string-keyed registry and was deliberately not pursued (over-engineered for dev-time authoring).

---

## Inputs
| Input | Source |
|---|---|
| Resource name | From the invocation (e.g. "Chemistry") |
| What it covers / topic list | Ask the user if not given |
| Has special elements? | Ask — does it need Interaction auto-fill, or help topics only? |

---

## Routing
This touches **Foundation (module 2)** — two enum edits — so per the project rules it must go through **`!GenerateAPlan`** first. Generate the plan using the template below, get approval, then execute.

---

## The Recipe (what the plan must contain)

Template to copy: **`9 Resources/Sources/9.7 JSON Help/`** — the most recently added module, cleanest example.

### 1. Copy the sub-module folder
`9 Resources/Sources/9.7 JSON Help/` → `9.X <Name> Help/`, renaming all four types:
- `<Name>HelpContent.swift` — topic model (`id`, `title`, `category`, `searchTerms`, `body`)
- `<Name>HelpIndex.swift` — `actor`; loads `<name>_help_index.json` via `Bundle.module` with `subdirectory: "9.X <Name> Help"`
- `<Name>HelpCoordinator.swift` — `@MainActor`; context-sensitive lookup
- `<Name>HelpPanelView.swift` — wraps the generic `SputnikHelpPanel`

One responsibility per file (SR-6); index is an `actor`, coordinator/panel are `@MainActor` (SW-1).

### 2. Author content
`<name>_help_index.json` (+ any topic `.md` files) inside the new folder.

### 3. Register the bundle — DO NOT SKIP (ISS-045 footgun)
Add the new directory to the `resources:` block in **`9 Resources/Package.swift`** with `.process(...)`. If you miss this, the index loads zero topics silently and the panel appears empty with no error.

### 4. Foundation enum edits (the only module-2 touch)
- `2 Foundation/2.4 UI and UX/HelpTopic.swift` — add the `case` + its `title`.
- `2 Foundation/2.3 Settings/WritingAssistMatrix.swift` — add the `case` to `WritingAssistLanguage` **and** its row in `applies(_:to:)` (declare which of Instant-Correct / Auto-Complete / More-Context / Interaction apply).

Both enums are closed and exhaustively switched — adding a case keeps every `switch` compile-safe; check for any non-`default` switch on these enums that now needs the new case.

### 5. Wire the surfaces
- `2 Foundation/2.0 App Overview/HelpMenuGroup.swift` — add the `Button("<Name> Help")` and the per-language toggle rows in the More-Context / Interaction submenus.
- `9 Resources/Sources/SputnikHelpContextResolver.swift` — add the dispatch arm to the new coordinator.
- *(optional)* `9 Resources/Sources/9.8 Interaction/special_elements.json` + Foundation `ResourceLookup` — only if the resource has special elements driving Interaction auto-fill.

### 6. Tests + guide
- Extend `9 Resources/Tests/ResourcesModuleTests.swift` (index loads, search works) — mirror the existing per-index tests.
- Add/extend the Module Guide under `1 Setup/Module Guides/9 Resources/`.

---

## Plan File Format
Produce the plan via `!GenerateAPlan` (saved to `Plans New/`). Purpose = "Add the <Name> built-in help resource." Success condition = the entry appears in the Help menu, opens a populated `SputnikHelpPanel`, search/tabs work, toggles persist, and built-ins are unregressed.

---

## Rules
- Plan before code — route through `!GenerateAPlan` because Foundation is touched.
- **Always** register the new directory in `Package.swift` (Step 3) — the single most common failure (ISS-045).
- Copy an existing sub-module rather than writing from scratch — keeps the four-type shape and threading model consistent.
- No force-unwraps; index/coordinator follow the actor / `@MainActor` split (SR-2, SW-1).
- If the resource needs special elements, the `resourceLanguage` it references must be a real `WritingAssistLanguage` case added in Step 4.
- Closeout per `!GenerateAPlan`: update the Module Guide, commit `[9 Resources] Add <Name> help resource`, push, move plan to `Plans Completed/`.
