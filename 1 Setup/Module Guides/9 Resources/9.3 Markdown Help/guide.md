---
module: 9.3 Resources – Markdown Help
status: complete
last_updated: 2026-06-09
---

## Purpose
Provide a comprehensive library of detailed Markdown notes and syntax references (targeting **CommonMark** and **GitHub Flavored Markdown**) that opens as a **dedicated panel with tabbed navigation** — analogous to how HTML Preview (8) or PDF Viewer (5) occupy their own panel slot. Each topic you navigate to (from the sidebar, search, or right-click lookup) opens as a **new tab** inside the Markdown Help panel, so you can flip between multiple open references. The panel operates in two triggering modes: (1) opened directly from the menu or toolbar; and (2) context-sensitive lookup triggered by right-clicking a Markdown element, keyword, or selection in the Text Editor (3.2), which opens or raises the panel and creates a tab for the matched topic.

## Diagram

```
  ┌─ Sputnik Layout ────────────────────────────────────────────────┐
  │ ┌──────┐ ┌──────────────────────┐ ┌──────────────────────────┐  │
  │ │ File  │ │ Text Editor (3)      │ │  Markdown Help Panel     │  │
  │ │ Tree  │ │  [Markdown mode]     │ │  ┌──────────────────────┐│  │
  │ │ (6)   │ │                      │ │  │ ▸ Headings        ✕ ││  │
  │ │       │ │  ## Hello            │ │  │ ▸ Tables          ✕ ││  │
  │ │       │ │  This is **bold**    │ │  │ ▸ Links ───────── ✕ ││  │
  │ │       │ │                      │ │  └──────────────────────┘│  │
  │ └──────┘ └──────────────────────┘ │  ┌──────┬────────────────┐│  │
  │ ┌────────────────────────────────┐│  │Search│ Links           ││  │
  │ │ Terminal (7)                   ││  │      │ [text](url)     ││  │
  │ └────────────────────────────────┘│  │■ Inline    renders as  ││  │
  └──────────────────────────────────┘  │  Bold     a clickable   ││  │
                                        │  Italic   hyperlink.    ││  │
  The Markdown Help panel occupies      │  Code                    ││  │
  a panel slot in the layout, same      │  Links  [ Live Demo ]   ││  │
  as HTML Preview or PDF Viewer.        └─────────────────────────┘│  │
                                        └──────────────────────────┘  │
                                                                      │
  Panel lifecycle:                                                     │
  ┌────────────┐    ┌───────────────────┐    ┌──────────────────┐     │
  │ Menu/      │───▶│ InterPanelRouter  │───▶│ Open / raise     │     │
  │ Right-click│    │ (2.1)            │    │ panel + create   │     │
  └────────────┘    │ routed to 9.3    │    │ tab for topic    │     │
                    └───────────────────┘    └──────────────────┘     │
```

### Mode Details

| Aspect | Mode 1: Menu / Toolbar | Mode 2: Context Lookup (right-click) |
|---|---|---|
| **Trigger** | Menu item `Help > Markdown Help`, toolbar `?` button, or keyboard shortcut | Right-click context menu on selected text in Text Editor (3.2) when editor mode is `.markdown` |
| **Panel action** | Opens the Markdown Help panel (if closed) or raises it (if open), with the last-viewed topic or the topic index as the initial tab | Opens or raises the panel and creates a **new tab** for the matched topic; does not replace existing tabs |
| **Navigation** | Free — user browses sidebar topics or types in the search bar | Automatic — panel jumps to the best-matching topic; user can then browse normally in the same tab |
| **Tab behaviour** | Each topic clicked in the sidebar opens as a **new tab** (or re-activates an existing tab for the same topic ID). Tabs are closable (✕), reorderable by drag. The tab bar shows topic titles. | Same — the lookup result opens in a new tab. If the same topic is already open in a tab, that tab is activated instead of creating a duplicate. |
| **Panel state** | Remembers open tabs and active tab across session restarts via `PersistenceService` (2.5) | Tabs persist; closing the panel collapses it but preserves its tab state |

## Technical Summary
- **Framework(s):** SwiftUI, Foundation, Apple's **Swift Markdown** (CommonMark parsing)
- **Markdown Content:** Includes a built-in library of detailed Markdown notes covering **CommonMark** and **GFM** syntax, formatting, lists, and tables, with interactive 'source' vs 'rendered' examples.
- **Key types:**
  - `MarkdownHelpPanelView` — top-level SwiftUI view that registers as a panel in Foundation 2.4 (UI/UX) and manages a tab bar + the topic content area <!-- assumed -->
  - `MarkdownHelpTabView` — individual tab content wrapping `MarkdownHelpContentView` for a single topic. Tabs are identified by topic ID. <!-- assumed -->
  - `MarkdownHelpContentView` — the content area inside a tab: sidebar `List` of topics and a `ScrollView` rendering the current topic's content with live Markdown demos from Module 4's renderer <!-- assumed -->
  - `MarkdownHelpTab` — value type: `id: UUID` (topic ID), `title: String`, `dateOpened: Date` (for ordering) <!-- assumed -->
  - `MarkdownHelpPanelViewModel` — `@MainActor @Observable` class owning the open-tab list, active tab ID, and panel visibility; saved/restored via `PersistenceService` (2.5) <!-- assumed -->
  - `MarkdownHelpContent` — `Codable` value type: `id: UUID`, `title: String`, `category: String`, `body: String` (markdown — rendered inline by the app's Markdown renderer), `relatedTopics: [UUID]`, `exampleCode: String?` (a snippet shown in a code block with a "Render" toggle) <!-- assumed -->
  - `MarkdownHelpIndex` — loaded from `9 Resources/MarkdownHelp/index.json`; supports full-text search across `title`, `body`, and `category` <!-- assumed -->
  - `MarkdownHelpCoordinator` — receives context-lookup requests from `InterPanelRouter` (2.1); maps the query (potentially enriched with `cursorContext` like `## ` prefix) to a help topic; opens/creates a tab for the result <!-- assumed -->
- **Content source:** Help topics live as `.md` files in `9 Resources/MarkdownHelp/`, organised by category subdirectory. An `index.json` at the root lists every topic with its title, category, tags (for search), and optional `exampleCode` snippets. The body is full Markdown — including fenced code blocks, tables, and embedded `@{help:uuid}` cross-reference links — rendered live by the same Markdown rendering pipeline used by Module 4.
- **Threading model:** Index loaded once on `Task(priority: .userInitiated)` and cached. Topic content loaded on demand. Search and navigation on `@MainActor`.
- **Data flow:**
  - *Panel open:* Menu/toolbar trigger → `InterPanelRouter` (2.1) routes to the Markdown Help panel via Foundation 2.4's panel registry → panel opens in its assigned layout slot → `MarkdownHelpPanelViewModel` restores tab state from `PersistenceService` → if no saved tabs, creates an initial index tab.
  - *Sidebar click:* User clicks a topic in the sidebar → `MarkdownHelpPanelViewModel.openTab(topicID:)` — if a tab for this topic already exists, activate it; otherwise create a new tab, load the `.md` file, render through Markdown engine (4), append to tab list.
  - *Context lookup:* User right-clicks in editor (3.2) → context menu analyses the cursor context (`## ` → heading, `**text**` → bold, `[text](url)` → link, selected text as search query) → `InterPanelRouter` sends `{source: .editor, query: <parsed-topic>, fileType: .markdown, cursorContext: <raw-prefix>}` → `MarkdownHelpCoordinator` searches index for best match → calls `MarkdownHelpPanelViewModel.openTab(topicID:)` which opens/raises the panel and activates/creates the tab. Falls back to the search results page with the query pre-filled if no match.
  - *Tab close:* User clicks ✕ on a tab → `MarkdownHelpPanelViewModel.closeTab(tabID:)` — if it was the last tab, show the topic index; if the panel itself is closed (collapse), tabs are preserved in memory and persisted.
  - *Live demos:* Some topics include `exampleCode` — the view renders the snippet as both raw Markdown code and a live preview side by side, using Module 4's renderer to display the output.
- **State owned:** Open tab list (`[MarkdownHelpTab]`), active tab ID, panel visibility (collapsed vs open). This state is persisted via `PersistenceService` (2.5) so the panel restores its tabs on relaunch.
- **Dependencies:** Module 4 Markdown Preview (rendering help content body for live demos); Foundation 2.1 InterPanelRouter (context lookup + panel open/raise routing); Foundation 2.4 UI/UX (panel slot registration, tab bar chrome); Foundation 2.5 PersistenceService (tab state persistence); Text Editor 3.2 (context-menu trigger, `.markdown` editor mode).
- **Failure modes:**
  - Context lookup query resolves to nothing → help panel opens/shows at the search results page with query pre-filled; no spurious tab is created.
  - Help index missing or corrupt → panel shows a "Help not available" placeholder; context lookup does nothing (no crash, SR-2).
  - Markdown rendering dependency (4) not available → help body is shown as raw Markdown text (graceful degradation); inline live demos show a "Renderer unavailable" note instead of the preview.
  - Cross-referenced topic (`@{help:uuid}`) is missing → the link is rendered as plain text with a "Topic not found" style; no crash.
  - Persisted tab state references a topic that no longer exists in the index → that tab is silently dropped on restore; the panel opens with the topic index instead.
