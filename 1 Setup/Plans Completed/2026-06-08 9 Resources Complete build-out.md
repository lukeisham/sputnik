---
plan: Complete build-out
module: 9 Resources
created: 2026-06-08
status: complete
related_issues: none
---

## Purpose
Build the complete Resources module — the ASCII Library (9.1) with its index, art content, and search actor, plus four interactive help panels (ASCII Art 9.2, Markdown 9.3, HTML 9.4, Grammar 9.5) each with tabbed navigation, search, context-sensitive lookup from the editor/preview panels, and state persistence — and wire the help panels into Foundation's `HelpTopic` routing so the Help menu presents them correctly.

## Success Condition
The app compiles cleanly. Opening any help topic from the Help menu (`Help > Markdown Help`, etc.) presents the correct help panel with its sidebar, search bar, and topic content. Switching between help topics switches the active panel. Each help panel's tab state (open tabs, active tab) survives an app restart. The ASCII Library actor loads `index.json`, serves search results, and returns art content on demand.

## Steps

- [x] 1. **Add `PanelID` cases for help panels to Foundation**
   What: Add `.asciiArtHelp`, `.markdownHelp`, `.htmlHelp`, `.grammarHelp` cases to `PanelID` in `2 Foundation/2.4 UI and UX/PanelID.swift`.
   Why: The guide diagrams show each help panel occupying a layout slot like PDF Viewer or HTML Preview, but `PanelID` currently has no help-panel cases. Foundation owns `PanelID` (SR-1), so this is the required Foundation touchpoint. *Flagged: Foundation change — all other modules must be aware that 4 new panel IDs exist.*

- [x] 2. **Extend `PanelLayout.default` with help-panel slot assignments**
   What: In `PanelLayout.swift`, add a mapping from each new `PanelID` help case to a `PanelPosition` (all four map to `.right` by default, since only one help panel is visible at a time — they share the slot). Also add them to `visibility` defaults (initially hidden).
   Why: Without layout assignments, the help panels have no position to render into, and the panel registry in `ContentView` has nothing to wire.

- [x] 3. **Observe `AppState.requestedHelpTopic` to drive help-panel visibility**
   What: In `AppState` or the assembly layer (`ContentView` / a new `HelpPanelRouter`), observe changes to `requestedHelpTopic` — when set, show the corresponding help panel in its assigned slot and hide the other help panels; when cleared, hide all help panels.
   Why: `AppState.requestedHelpTopic` is the single Help-menu trigger. The help panels must react to it. This is the glue between the Help menu (Foundation 2.6) and the Resources module (9.2–9.5) per SR-1 (communication via Foundation).

- [x] 4. **Build `SputnikHelpPanel` — the shared help-panel container (tab bar + search + sidebar + content area)**
   What: Create a reusable SwiftUI view `SputnikHelpPanel` in `9 Resources/` that accepts a generic `HelpContent` type and handles: tab bar (add/select/close/reorder), search bar with debounced query, sidebar category list, and a content area. Persist open-tab state via `PersistenceService` using a dedicated persistence key per panel. Re-activate existing tabs when the same topic is opened again. Drop tabs referencing deleted topics on restore.
   Why: All four help sub-modules (9.2–9.5) share identical UX — a tabbed panel with sidebar + search + content. Building a single generic container avoids quadruplicating the tab/sidebar/search/view-model logic and keeps each sub-module focused only on its content type and coordinator. The shared container also guarantees consistent tab-close, reorder, search-debounce, and persistence behaviour across all help panels.

- [x] 5. **Build ASCII Library (9.1): index.json, art files, and `ASCIILibrary` actor**
   What: Create `9 Resources/9.1 ASCIILibrary/index.json` with metadata records for every art piece. Populate category directories with `.txt` art files (at least 3–5 pieces per category: Arrows, Decorative, Dividers, Frames, Symbols — ~20 pieces total). Create `ASCIILibrary` actor (`ASCIILibrary.swift`) that loads the index on init, exposes `search(query:) -> [ASCIIArtRecord]`, `art(id:) -> String?`, and `categories() -> [String]`. Create `ASCIIArtRecord` (Codable, Sendable) and `ASCIILibraryIndex` types. Package the library as `ASCIILibrary.bundle` via Xcode build phase (or load from the main bundle resource path for now). Handle missing/malformed index gracefully per SR-2.
   Why: The ASCII Library is the data foundation for both the Text Editor's ghost-text suggestions (3.3) and the ASCII Art Help panel's inline examples (9.2). It must be built first so the help panel can reference real art. All guides describe it as a prerequisite (dependencies section in 9.2).

- [x] 6. **Build ASCII Art Help content (9.2): index.json and topic `.md` files**
   What: Create `9 Resources/9.2 ASCII art Help/index.json` with ~10 topics covering drawing shapes, borders, animals, decorations, text art, arrows, dividers, frames, symbols, and layout patterns. Create corresponding `.md` files in category subdirectories (`basics/`, `techniques/`, `examples/`). Each topic embeds `@{art:uuid}` placeholders that resolve to `ASCIILibrary` art at display time. Include at least one `exampleCode` snippet per topic showing before/after art composition.
   Why: The help panel needs content to display. The guide's content-source spec calls for `.md` files + `index.json`. Placeholder resolution via `@{art:uuid}` is the bridge between the help content and the ASCII Library (9.1).

- [x] 7. **Build ASCII Art Help panel view + coordinator (9.2)**
   What: Create `ASCIIArtHelpPanelView.swift` (wraps `SputnikHelpPanel` with `ASCIIArtHelpContent`), `ASCIIArtHelpCoordinator.swift` (receives context-lookup from `InterPanelRouter` when editor mode is `.asciiArt`), `ASCIIArtHelpContent.swift` (Codable value type matching the guide spec), and `ASCIIArtHelpIndex.swift` (loads the index, supports full-text search). Register the panel in `ContentView` under the `.asciiArtHelp` `PanelID`. Render `@{art:uuid}` placeholders by calling `ASCIILibrary.art(id:)` and displaying the result in a code block.
   Why: This is the first complete help panel implementation. It validates the shared `SputnikHelpPanel` container, the `HelpTopic` routing, the `PanelID` registration, and the `@{art:uuid}` placeholder pipeline. It also exercises the ASCII Library (9.1) cross-module dependency.

- [x] 8. **Build Markdown Help content (9.3): index.json and topic `.md` files**
   What: Create `9 Resources/9.3 Markdown Help/index.json` with ~10 topics covering headings, bold/italic, links, images, lists, code blocks, tables, blockquotes, horizontal rules, and GFM extensions. Create `.md` files in category subdirectories (`basics/`, `formatting/`, `advanced/`). Include `exampleCode` snippets and `relatedTopics` cross-references. Some topics include `@{help:uuid}` links to other topics. Each topic body is full Markdown rendered by the app's Markdown rendering pipeline (Module 4).
   Why: Content is the value proposition of a help panel. The `.md` file format is the source of truth per the guide. `exampleCode` snippets with "Render" toggles let users see raw Markdown vs rendered output side by side.

- [x] 9. **Build Markdown Help panel view + coordinator (9.3)**
   What: Create `MarkdownHelpPanelView.swift`, `MarkdownHelpCoordinator.swift`, `MarkdownHelpContent.swift`, and `MarkdownHelpIndex.swift`. Same structure as ASCII Art Help, but: (a) content body is rendered through Module 4's Markdown renderer, not plain text; (b) `exampleCode` snippets get a "Render" toggle showing live Markdown preview; (c) context lookup from the editor (3.2) analyses cursor context (`## ` → heading, `**text**` → bold, etc.) to match the best topic. Gracefully degrade to raw Markdown text display if Module 4's renderer is unavailable.
   Why: This is the second help panel — it validates the shared container pattern with a different content type and introduces live rendering as a feature. The cursor-context analysis for right-click lookup is more sophisticated than ASCII Art's simple keyword search.

- [x] 10. **Build HTML Help content (9.4): index.json and topic `.md` files**
   What: Create `9 Resources/9.4 Html Help/index.json` with ~12 topics covering common elements (`<div>`, `<span>`, `<table>`, `<a>`, `<img>`, `<form>`, `<input>`, `<button>`, `<ul>/<ol>`, `<head>`, `<body>`, `<meta>`), key attributes (`class`, `id`, `style`, `href`, `src`), global attributes, and best-practice guides. Create `.md` files in subdirectories (`elements/`, `attributes/`, `globals/`, `events/`, `guides/`). Topics that describe visual elements include `exampleHTML` snippets for live WKWebView demos.
   Why: HTML is the most visually rich help content (live HTML demos). The content structure mirrors the guide's subdirectory layout and the `HTMLHelpContent` type spec.

- [x] 11. **Build HTML Help panel view + coordinator (9.4)**
   What: Create `HTMLHelpPanelView.swift`, `HTMLHelpCoordinator.swift`, `HTMLHelpContent.swift`, and `HTMLHelpIndex.swift`. Same shared-container pattern, plus: (a) `exampleHTML` snippets render in a sandboxed `WKWebView` (~200 px tall) inside the content scroll view; (b) each tab with a live demo owns its own `WKWebView` instance, deallocated on tab close (SR-3); (c) context lookup from the editor (3.4) extracts tag names (`<tagname`) and attribute names (`attr="..."`) for matching. Sandbox the `WKWebView`: no navigation, no script execution, static rendering only per the guide.
   Why: The live HTML demo feature is unique to this help panel and is the main differentiator. The `WKWebView` sandboxing is critical for security and memory (SR-3). Tab-level `WKWebView` lifecycle ensures RAM stays bounded.

- [x] 12. **Build Grammar Help content (9.5): index.json and topic `.md` files**
   What: Create `9 Resources/9.5 Grammar Help/index.json` with ~12 topics covering punctuation (commas, semicolons, colons, periods, apostrophes), grammar (subject-verb agreement, verb tense, pronoun case, modifiers), style (active/passive voice, conciseness), spelling/usage (their/there/they're, its/it's, affect/effect). Create `.md` files in subdirectories (`punctuation/`, `grammar/`, `style/`, `spelling/`, `usage/`). Each topic includes `searchTerms` (fuzzy-match aliases) and `✅`/`❌` example blocks. The `searchTerms` array is critical — it maps arbitrary user-selected words (e.g. "there", "their", "they're") to the correct topic.
   Why: Grammar Help has unique fuzzy-matching requirements. The `searchTerms` field is the bridge between a random word a user right-clicks and the correct grammar rule. The ✅/❌ formatting is a visual differentiator for this panel.

- [x] 13. **Build Grammar Help panel view + coordinator (9.5)**
   What: Create `GrammarHelpPanelView.swift`, `GrammarHelpCoordinator.swift`, `GrammarHelpContent.swift`, and `GrammarHelpIndex.swift`. Same shared-container pattern, plus: (a) render `✅`/`❌` blocks with distinct styling (green check / red cross); (b) context lookup accepts from **both** `.editor` and `.markdownPreview` sources (dual-panel lookup — unique among help modules); (c) the coordinator searches by `title` and `searchTerms`, and when a word maps to multiple topics (e.g. "run" → verb tense vs noun usage), returns the top match and includes a "See also" list. (d) Integrate with the spelling/grammar checker (3.5): when a grammar-underlined word is right-clicked, the context menu shows "Grammar: <word>" alongside the correction suggestion.
   Why: Grammar Help is the most architecturally complex help panel — it accepts lookups from two different panel sources (editor + Markdown preview) and integrates with the spelling/grammar checker's right-click menu. The `searchTerms` fuzzy-matching and "See also" disambiguation are unique requirements.

- [x] 14. **Wire help panels into `ContentView`**
   What: In `ContentView.swift` (2.6), add conditional rendering for each of the four help panels based on their `PanelID` slot assignment and visibility. Pass `AppState` as `@Environment`. Each help panel's ViewModel is created once and stored as `@State`. Wire the Help menu's `requestedHelpTopic` observation so that selecting a help topic shows the corresponding panel.
   Why: `ContentView` is the root layout. The help panels must be wired into the panel slot grid just like PDF Viewer and HTML Preview. This is the assembly step that makes the panels actually render.

- [x] 15. **Integration validation — end-to-end smoke test**
   What: Launch the app. Open `Help > ASCII Art Help` — verify panel appears with sidebar, search, and topic content. Click a topic — verify new tab opens. Search for "border" — verify results. Right-click `:cat` in ASCII art editor mode — verify context lookup opens the panel. Switch to `Help > Markdown Help` — verify the ASCII Art panel hides and Markdown Help shows. Repeat for HTML and Grammar. Quit and relaunch — verify tab state is restored. Verify that opening the same topic twice activates the existing tab rather than creating a duplicate.
   Why: This validates the full vertical slice: Foundation routing → panel slot assignment → shared container → per-panel content loading → persistence → context lookup → tab lifecycle. Every Vibe Rule is exercised (SR-1 module isolation, SR-2 no crashes on missing content, SR-3 lazy loading, SR-4 off-main-thread index loading).

## Risks and Constraints

- **Foundation touchpoint constraint**: Steps 1–3 and 14 modify Foundation files (`PanelID`, `PanelLayout`, `ContentView`). Per SR-1, Foundation owns these types and the changes are scoped to adding new enum cases, new default-layout mappings, and new conditional-rendering branches. No existing behaviour is changed. The plan is self-contained — it does not require changes to Text Editor, PDF Viewer, Markdown Preview, HTML Preview, or Terminal.

- **No PanelID cases for help panels today**: `PanelID` currently has 5 cases (`fileTree`, `textEditor`, `markdownPreview`, `htmlPreview`, `pdfViewer`). Adding 4 new cases brings it to 9. All existings `switch` exhaustiveness checks will need updating — but since `PanelID` is `CaseIterable` and used with SwiftUI's `switch`, the compiler will catch every site, making this a safe change.

- **All four help panels share a single `PanelPosition` (`.right`)**: Only one help panel is visible at a time (driven by `requestedHelpTopic`), so they share the right slot. This avoids layout complexity. If the user wants to see two help panels simultaneously in the future, a second slot can be assigned.

- **ASCII Library loads via Bundle, not a separate `.bundle` target**: Building a separate `ASCIILibrary.bundle` target requires Xcode project configuration outside the scope of this plan. Instead, art files and `index.json` are stored in `9 Resources/9.1 ASCIILibrary/` and loaded from the main app bundle at runtime. This is simpler and functionally equivalent per the guide's "Bundle layout" description.

- **Help content authoring scope**: This plan creates a representative sample of content for each sub-module (~10–20 topics/art pieces each). The full library of hundreds of topics is a content-authoring effort beyond a single coding plan. The infrastructure is designed to scale: adding a topic is just a new `.md` file + an entry in `index.json`, with zero code changes.

- **Markdown Help depends on Module 4's renderer**: Module 4 (Markdown Preview) must be at least partially built for Markdown Help to render topic bodies. If Module 4 is not yet available, the Markdown Help panel degrades gracefully to raw Markdown text display per the guide's failure mode. This plan does not block on Module 4.

- **HTML Help's live demos depend on WebKit**: The `WKWebView` sandboxing (no navigation, no scripts) is critical. A misconfigured `WKWebView` could execute arbitrary HTML/JS. The plan documents the exact sandboxing configuration in Step 11.

## Files Affected

### Foundation (steps 1–3, 14)
- `2 Foundation/2.4 UI and UX/PanelID.swift` — add `.asciiArtHelp`, `.markdownHelp`, `.htmlHelp`, `.grammarHelp`
- `2 Foundation/2.4 UI and UX/PanelLayout.swift` — add default slot assignments for new PanelIDs (all → `.right`), add to visibility defaults
- `2 Foundation/2.6 App Lifecycle/ContentView.swift` — add conditional panel rendering for each help panel, wire `requestedHelpTopic` observation

### ASCII Library (9.1) — step 5
- `9 Resources/9.1 ASCIILibrary/index.json` — art metadata index (new)
- `9 Resources/9.1 ASCIILibrary/Arrows/*.txt` — arrow art files (new, ~3–5)
- `9 Resources/9.1 ASCIILibrary/Decorative/*.txt` — decorative art files (new, ~3–5)
- `9 Resources/9.1 ASCIILibrary/Dividers/*.txt` — divider art files (new, ~3–5)
- `9 Resources/9.1 ASCIILibrary/Frames/*.txt` — frame art files (new, ~3–5)
- `9 Resources/9.1 ASCIILibrary/Symbols/*.txt` — symbol art files (new, ~3–5)
- `9 Resources/ASCIILibrary.swift` — `ASCIILibrary` actor, `ASCIIArtRecord`, `ASCIILibraryIndex` (new)
- `9 Resources/ASCIIArtRecord.swift` — value type (new)
- `9 Resources/ASCIILibraryIndex.swift` — index container (new)

### ASCII Art Help (9.2) — steps 6–7
- `9 Resources/9.2 ASCII art Help/index.json` — topic metadata index (new)
- `9 Resources/9.2 ASCII art Help/basics/*.md` — basic topics (new, ~3)
- `9 Resources/9.2 ASCII art Help/techniques/*.md` — technique topics (new, ~3)
- `9 Resources/9.2 ASCII art Help/examples/*.md` — example topics (new, ~3)
- `9 Resources/ASCIIArtHelpPanelView.swift` — SwiftUI panel view (new)
- `9 Resources/ASCIIArtHelpCoordinator.swift` — context lookup coordinator (new)
- `9 Resources/ASCIIArtHelpContent.swift` — content value type (new)
- `9 Resources/ASCIIArtHelpIndex.swift` — index loader (new)
- `9 Resources/SputnikHelpPanel.swift` — shared help panel container (new, step 4)

### Markdown Help (9.3) — steps 8–9
- `9 Resources/9.3 Markdown Help/index.json` — topic metadata index (new)
- `9 Resources/9.3 Markdown Help/basics/*.md` — basic topics (new, ~3)
- `9 Resources/9.3 Markdown Help/formatting/*.md` — formatting topics (new, ~3)
- `9 Resources/9.3 Markdown Help/advanced/*.md` — advanced topics (new, ~3)
- `9 Resources/MarkdownHelpPanelView.swift` — SwiftUI panel view (new)
- `9 Resources/MarkdownHelpCoordinator.swift` — context lookup coordinator (new)
- `9 Resources/MarkdownHelpContent.swift` — content value type (new)
- `9 Resources/MarkdownHelpIndex.swift` — index loader (new)

### HTML Help (9.4) — steps 10–11
- `9 Resources/9.4 Html Help/index.json` — topic metadata index (new)
- `9 Resources/9.4 Html Help/elements/*.md` — element topics (new, ~5)
- `9 Resources/9.4 Html Help/attributes/*.md` — attribute topics (new, ~2)
- `9 Resources/9.4 Html Help/globals/*.md` — global attribute topics (new, ~2)
- `9 Resources/9.4 Html Help/events/*.md` — event topics (new, ~1)
- `9 Resources/9.4 Html Help/guides/*.md` — guide topics (new, ~2)
- `9 Resources/HTMLHelpPanelView.swift` — SwiftUI panel view (new)
- `9 Resources/HTMLHelpCoordinator.swift` — context lookup coordinator (new)
- `9 Resources/HTMLHelpContent.swift` — content value type (new)
- `9 Resources/HTMLHelpIndex.swift` — index loader (new)

### Grammar Help (9.5) — steps 12–13
- `9 Resources/9.5 Grammar Help/index.json` — topic metadata index (new)
- `9 Resources/9.5 Grammar Help/punctuation/*.md` — punctuation topics (new, ~3)
- `9 Resources/9.5 Grammar Help/grammar/*.md` — grammar topics (new, ~3)
- `9 Resources/9.5 Grammar Help/style/*.md` — style topics (new, ~2)
- `9 Resources/9.5 Grammar Help/spelling/*.md` — spelling/usage topics (new, ~2)
- `9 Resources/9.5 Grammar Help/usage/*.md` — usage topics (new, ~2)
- `9 Resources/GrammarHelpPanelView.swift` — SwiftUI panel view (new)
- `9 Resources/GrammarHelpCoordinator.swift` — context lookup coordinator (new)
- `9 Resources/GrammarHelpContent.swift` — content value type (new)
- `9 Resources/GrammarHelpIndex.swift` — index loader (new)

## Closeout
- [x] Re-read the Purpose statement — does the outcome match it exactly?
- [x] Success Condition verified (ran / tested / confirmed as described above)
- [x] Module Guide(s) updated (`status` + `last_updated`)
- [x] Changes committed: `[9 Resources] Complete build-out`
- [x] Pushed to GitHub
- [x] Plan moved to Plans Completed/
