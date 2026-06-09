---
module: 9.5 Resources – Grammar Help
status: draft
last_updated: 2026-06-08
---

## Purpose
Provide a comprehensive library of detailed English Grammar notes and style references that opens as a **dedicated panel with tabbed navigation** — analogous to how HTML Preview (8) or PDF Viewer (5) occupy their own panel slot. Each topic you navigate to (from the sidebar, search, or right-click lookup) opens as a **new tab** inside the Grammar Help panel, so you can flip between multiple open references. The panel operates in three triggering modes: (1) opened directly from the menu or toolbar; (2) context-sensitive lookup triggered by right-clicking a word or phrase in the Text Editor (3.1/3.5); and (3) context-sensitive lookup triggered by right-clicking a word or phrase in the **Markdown Preview** (Module 4) — making Grammar Help the only help module with dual-panel context lookup.

## Diagram

```
  ┌─ Sputnik Layout ──────────────────────────────────────────────────┐
  │ ┌──────┐ ┌──────────────────────┐ ┌────────────────────────────┐  │
  │ │ File  │ │ Text Editor (3)      │ │  Grammar Help Panel        │  │
  │ │ Tree  │ │                      │ │  ┌────────────────────────┐│  │
  │ │ (6)   │ │  The dog run fast.   │ │  │ ▸ S-V Agreement     ✕ ││  │
  │ │       │ │        ~~~~~~~~      │ │  │ ▸ Their/There/They're││  │
  │ │       │ │  (grammar underline) │ │  │ ▸ Comma Usage ───── ✕ ││  │
  │ │       │ │                      │ │  └────────────────────────┘│  │
  │ └──────┘ └──────────────────────┘ │  ┌──────┬─────────────────┐ │  │
  │ ┌────────────────────────────────┐│  │Search│ S-V Agreement    │ │  │
  │ │ Terminal (7)                   ││  │      │                   │ │  │
  │ └────────────────────────────────┘│  │■ Punctuation           │ │  │
  └──────────────────────────────────┘  │  Comma     ✅ The dog   │ │  │
                                        │  Semicolon    runs.    │ │  │
  The Grammar Help panel occupies       │  Colon     ❌ The dog   │ │  │
  a panel slot in the layout, same      │  Period       run.     │ │  │
  as HTML Preview or PDF Viewer.        └─────────────────────────┘ │  │
                                        └────────────────────────────┘  │
                                                                        │
  Panel lifecycle:                                                       │
  ┌────────────┐    ┌───────────────────┐    ┌──────────────────┐       │
  │ Menu/      │───▶│ InterPanelRouter  │───▶│ Open / raise     │       │
  │ Right-click│    │ (2.1)            │    │ panel + create   │       │
  └────────────┘    │ routed to 9.5    │    │ tab for topic    │       │
                    └───────────────────┘    └──────────────────┘       │
```

### Mode Details

| Aspect | Mode 1: Menu / Toolbar | Mode 2: Editor Lookup | Mode 3: Preview Lookup |
|---|---|---|---|
| **Trigger** | Menu `Help > Grammar Help`, toolbar `?` button, or keyboard shortcut | Right-click context menu on a word in Text Editor (any mode — 3.1, 3.2, 3.3, 3.4, 3.5) | Right-click context menu on a word in Markdown Preview (Module 4) — the rendered preview captures the underlying text |
| **Panel action** | Opens the Grammar Help panel (if closed) or raises it (if open), with the last-viewed topic or the topic index as the initial tab | Opens or raises the panel and creates a **new tab** for the matched topic; does not replace existing tabs | Same as editor lookup — opens/raises panel and creates a new tab for the matched topic |
| **Navigation** | Free — browse sidebar topics or search | Automatic — panel jumps to the best-matching grammar topic for the selected word | Same — jumps to the best-matching topic |
| **Tab behaviour** | Each topic clicked in the sidebar opens as a **new tab** (or re-activates an existing tab for the same topic ID). Tabs are closable (✕), reorderable by drag. The tab bar shows topic titles. | Same — the lookup result opens in a new tab. If the same topic is already open in a tab, that tab is activated instead of creating a duplicate. | Same |
| **Panel state** | Remembers open tabs and active tab across session restarts via `PersistenceService` (2.5) | Tabs persist; closing the panel collapses it but preserves its tab state | Same |

## Technical Summary
- **Framework(s):** SwiftUI, Foundation
- **Grammar Content:** Includes a built-in library of detailed English Grammar notes covering punctuation, syntax, usage, and style, with interactive "correct" (✅) vs "incorrect" (❌) examples.
- **Key types:**
  - `GrammarHelpPanelView` — top-level SwiftUI view that registers as a panel in Foundation 2.4 (UI/UX) and manages a tab bar + the topic content area <!-- assumed -->
  - `GrammarHelpTabView` — individual tab content wrapping `GrammarHelpContentView` for a single topic. Tabs are identified by topic ID. <!-- assumed -->
  - `GrammarHelpContentView` — the content area inside a tab: sidebar `List` of grammar categories and a detail `ScrollView` rendering help content with examples and "correct" / "incorrect" formatting <!-- assumed -->
  - `GrammarHelpTab` — value type: `id: UUID` (topic ID), `title: String`, `dateOpened: Date` (for ordering) <!-- assumed -->
  - `GrammarHelpPanelViewModel` — `@MainActor @Observable` class owning the open-tab list, active tab ID, and panel visibility; saved/restored via `PersistenceService` (2.5) <!-- assumed -->
  - `GrammarHelpContent` — `Codable` value type: `id: UUID`, `title: String`, `category: String` (punctuation / grammar / style / spelling / usage), `body: String` (styled text with `✅`/`❌` formatting), `relatedTopics: [UUID]`, `searchTerms: [String]` (alternative queries like "their/there/they're" that map to this topic) <!-- assumed -->
  - `GrammarHelpIndex` — loaded from `9 Resources/GrammarHelp/index.json`; supports full-text search across `title`, `body`, `category`, and `searchTerms` <!-- assumed -->
  - `GrammarHelpCoordinator` — receives context-lookup requests from `InterPanelRouter` (2.1) originating from either `.editor` or `.markdownPreview` sources; maps the query word to the best grammar topic (using `searchTerms` for fuzzy matches); opens/creates a tab for the result <!-- assumed -->
- **Content source:** Help topics live as `.md` files in `9 Resources/GrammarHelp/`, organised by category subdirectory. An `index.json` at the root lists every topic with its `searchTerms` array — this is critical for context lookup because users may select any arbitrary word, and the index must map it (e.g. "there", "their", "they're" all map to "There / Their / They're"). Topics include example sentences formatted as correct (`✅`) and incorrect (`❌`) blocks.
- **Threading model:** Index loaded once on `Task(priority: .userInitiated)` and cached. Topic content loaded on demand. Search and navigation on `@MainActor`.
- **Data flow:**
  - *Panel open:* Menu/toolbar trigger → `InterPanelRouter` (2.1) routes to the Grammar Help panel via Foundation 2.4's panel registry → panel opens in its assigned layout slot → `GrammarHelpPanelViewModel` restores tab state from `PersistenceService` → if no saved tabs, creates an initial index tab.
  - *Sidebar click:* User clicks a topic in the sidebar → `GrammarHelpPanelViewModel.openTab(topicID:)` — if a tab for this topic already exists, activate it; otherwise create a new tab, load the `.md` file, render with styled correct/incorrect blocks and cross-references, append to tab list.
  - *Editor lookup (Mode 2):* User right-clicks selected text in plain-text or grammar mode in the Text Editor → "Look Up in Grammar Help" context item (added by `EditorTextView.menu(for:)` in 3.1) → `GrammarHelpCoordinator.lookup(word:source:)` resolves the best matching topic → result is written as a `HelpRequest(kind: .grammar, topicID: <id>)` to `AppState.requestedHelpTarget` → `GrammarHelpPanelView` observes the change via `SputnikHelpPanel.navigate(to:)` → panel reveals (opacity 1 in `ContentView.rightColumn`) and opens/activates the tab for `topicID`. Falls back to revealing the panel at overview when no topic matches.
  - *Markdown Preview lookup (Mode 3):* User right-clicks a word in the Markdown Preview (Module 4) → the preview's `NSTextView` (or equivalent) provides word-level hit testing → context menu shows "Grammar: <word>" → `InterPanelRouter` sends `{source: .markdownPreview, query: <word>, fileType: .markdown, cursorContext: <sentence>}` → same `GrammarHelpCoordinator` path → opens/creates a tab. This is the only help module that accepts context lookups from a non-editor panel.
  - *Spelling/Grammar integration (3.5):* When the inline grammar checker (3.5) underlines a word, right-clicking that word shows both the built-in correction suggestion and "Grammar: <word>" — using the same InterPanelRouter path as the manual right-click, creating a tab for the grammar rule.
  - *Tab close:* User clicks ✕ on a tab → `GrammarHelpPanelViewModel.closeTab(tabID:)` — if it was the last tab, show the topic index; if the panel itself is closed (collapse), tabs are preserved.
- **State owned:** Open tab list (`[GrammarHelpTab]`), active tab ID, panel visibility (collapsed vs open). This state is persisted via `PersistenceService` (2.5) so the panel restores its tabs on relaunch.
- **Dependencies:** Foundation 2.1 InterPanelRouter (context lookup from both `.editor` and `.markdownPreview` sources, plus panel open/raise routing); Foundation 2.4 UI/UX (panel slot registration, tab bar chrome); Foundation 2.5 PersistenceService (tab state persistence); Text Editor 3.5 (spelling/grammar checker integration, right-click trigger); Markdown Preview 4 (right-click trigger source for Mode 3).
- **Failure modes:**
  - Context lookup query resolves to nothing → help panel opens/shows at the search results page with query pre-filled; no spurious tab is created.
  - Help index missing or corrupt → panel shows a "Help not available" placeholder; context lookups from both editor and preview do nothing (no crash, SR-2).
  - A word that could map to multiple topics (e.g. "run" → verb tense, noun usage) → the coordinator returns the top-ranked match and includes a "See also" list of related topics in the content view; the user can navigate to the alternative topic from there (which opens in a new tab).
  - Markdown Preview right-click fires but the preview has no word-level text (e.g. an image caption is empty) → no context menu item is shown; no empty lookup is attempted.
  - Cross-referenced topic (`relatedTopics`) is missing → the link renders as styled text with a "Topic not found" indicator; no crash.
  - Persisted tab state references a topic that no longer exists in the index → that tab is silently dropped on restore; the panel opens with the topic index instead.
