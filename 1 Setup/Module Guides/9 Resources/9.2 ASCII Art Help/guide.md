---
module: 9.2 Resources – ASCII Art Help
status: draft
last_updated: 2026-06-08
---

## Purpose
Provide a browsable and searchable ASCII art reference that opens as a **dedicated panel with tabbed navigation** — analogous to how HTML Preview (8) or PDF Viewer (5) occupy their own panel slot. Each topic you navigate to (from the sidebar, search, or right-click lookup) opens as a **new tab** inside the ASCII Art Help panel, so you can flip between multiple open references. The panel operates in two triggering modes: (1) opened directly from the menu or toolbar; and (2) context-sensitive lookup triggered by right-clicking an ASCII art block or keyword in the Text Editor (3.3), which opens or raises the panel and creates a tab for the matched topic.

## Diagram

```
  ┌─ Sputnik Layout ──────────────────────────────────────────────┐
  │ ┌──────┐ ┌────────────────────┐ ┌──────────────────────────┐ │
  │ │ File  │ │ Text Editor (3)    │ │  ASCII Art Help Panel    │ │
  │ │ Tree  │ │                    │ │  ┌──────────────────────┐│ │
  │ │ (6)   │ │  :cat              │ │  │ ▸ Drawing Shapes  ✕ ││ │  ← tab bar
  │ │       │ │  ┌─────┐           │ │  │ ▸ Cat Art         ✕ ││ │
  │ │       │ │  │ ┌─┐ │           │ │  │ ▸ Box Borders ─── ✕ ││ │  ← active tab
  │ │       │ │  │ └─┘ │           │ │  └──────────────────────┘│ │
  │ │       │ │  └─────┘           │ │  ┌──────┬───────────────┐│ │
  │ └──────┘ └────────────────────┘ │  │Search│ Drawing Shapes ││ │
  │ ┌──────────────────────────────┐│  │      │                ││ │
  │ │ Terminal (7)                 ││  │■ Basics              ││ │
  │ └──────────────────────────────┘│  │  Lines    ┌─────┐    ││ │
  └────────────────────────────────┘  │  Boxes    │ ┌─┐ │    ││ │
                                      │  Curves   │ └─┘ │    ││ │
  The ASCII Art Help panel occupies   │■ Animals  └─────┘    ││ │
  a panel slot in the layout, same    │■ Borders             ││ │
  as HTML Preview or PDF Viewer.      └──────────────────────┘│ │
                                      └──────────────────────────┘ │
                                                                   │
  Panel lifecycle:                                                  │
  ┌────────────┐    ┌───────────────────┐    ┌──────────────────┐  │
  │ Menu/      │───▶│ InterPanelRouter  │───▶│ Open / raise     │  │
  │ Right-click│    │ (2.1)            │    │ panel + create   │  │
  └────────────┘    │ routed to 9.2    │    │ tab for topic    │  │
                    └───────────────────┘    └──────────────────┘  │
```

### Mode Details

| Aspect | Mode 1: Menu / Toolbar | Mode 2: Context Lookup (right-click) |
|---|---|---|
| **Trigger** | Menu item `Help > ASCII Art Help`, toolbar `?` button, or keyboard shortcut | Right-click context menu on selected text in Text Editor (3.3) when editor mode is `.asciiArt` |
| **Panel action** | Opens the ASCII Art Help panel (if closed) or raises it (if open), with the last-viewed topic or the topic index as the initial tab | Opens or raises the panel and creates a **new tab** for the matched topic; does not replace existing tabs |
| **Navigation** | Free — user browses sidebar topics or types in the search bar | Automatic — panel jumps to the best-matching topic; user can then browse normally in the same tab |
| **Tab behaviour** | Each topic clicked in the sidebar opens as a **new tab** (or re-activates an existing tab for the same topic ID). Tabs are closable (✕), reorderable by drag. The tab bar shows topic titles. | Same — the lookup result opens in a new tab. If the same topic is already open in a tab, that tab is activated instead of creating a duplicate. |
| **Panel state** | Remembers open tabs and active tab across session restarts via `PersistenceService` (2.5) | Tabs persist; closing the panel collapses it but preserves its tab state |

## Technical Summary
- **Framework(s):** SwiftUI, Foundation
- **Key types:**
  - `ASCIIArtHelpPanelView` — top-level SwiftUI view that registers as a panel in Foundation 2.4 (UI/UX) and manages a tab bar + the topic content area <!-- assumed -->
  - `ASCIIArtHelpTabView` — individual tab content wrapping `ASCIIArtHelpContentView` for a single topic. Tabs are identified by topic ID. <!-- assumed -->
  - `ASCIIArtHelpContentView` — the content area inside a tab: sidebar `List` of topics and a `ScrollView` rendering the current topic's content with inline ASCII art examples from the library <!-- assumed -->
  - `ASCIIArtHelpTab` — value type: `id: UUID` (topic ID), `title: String`, `dateOpened: Date` (for ordering) <!-- assumed -->
  - `ASCIIArtHelpPanelViewModel` — `@MainActor @Observable` class owning the open-tab list, active tab ID, and panel visibility; saved/restored via `PersistenceService` (2.5) <!-- assumed -->
  - `ASCIIArtHelpContent` — `Codable` value type representing a help topic: `id: UUID`, `title: String`, `category: String`, `body: String` (markdown), `relatedArtIDs: [UUID]` (cross-reference to `ASCIILibrary` records, shown as inline examples) <!-- assumed -->
  - `ASCIIArtHelpIndex` — loaded from `9 Resources/ASCIIArtHelp/index.json`; maps topic titles to content files; supports full-text search across `title` and `body` <!-- assumed -->
  - `ASCIIArtHelpCoordinator` — receives context-lookup requests from `InterPanelRouter` (2.1) with a `query` string; calls `search(query:)` on the help index and opens/creates a tab for the top result <!-- assumed -->
- **Content source:** Help topics live as `.md` files in `9 Resources/ASCIIArtHelp/`, organised by category subdirectory. An `index.json` at the root lists all topics with metadata. Content files embed `@{art:uuid}` placeholders that the view replaces with rendered ASCII art from the library (9.1) at display time.
- **Threading model:** Help index loading is done on a `Task(priority: .userInitiated)` on first panel appearance, cached for the session. Searches and topic rendering happen on `@MainActor`. Art content fetching (via 9.1) crosses the actor boundary but is `await`ed from the main actor.
- **Data flow:**
  - *Panel open:* Menu/toolbar trigger → `InterPanelRouter` (2.1) routes to the ASCII Art Help panel via Foundation 2.4's panel registry → panel opens in its assigned layout slot → `ASCIIArtHelpPanelViewModel` restores tab state from `PersistenceService` → if no saved tabs, creates an initial index tab.
  - *Sidebar click:* User clicks a topic in the sidebar → `ASCIIArtHelpPanelViewModel.openTab(topicID:)` — if a tab for this topic already exists, activate it; otherwise create a new tab, load the `.md` file, resolve `@{art:uuid}` placeholders via `ASCIILibrary.art(id:)`, append to tab list.
  - *Context lookup:* User right-clicks in editor (3.3) → context menu shows "Help: <selected text>" → `InterPanelRouter` sends `{source: .editor, query: <text>, fileType: .asciiArt}` → `ASCIIArtHelpCoordinator` receives it → searches index for best match → calls `ASCIIArtHelpPanelViewModel.openTab(topicID:)` which opens/raises the panel and activates/creates the tab. If no match found, opens the panel at the search results page with the query pre-filled.
  - *Tab close:* User clicks ✕ on a tab → `ASCIIArtHelpPanelViewModel.closeTab(tabID:)` — if it was the last tab, show the topic index; if the panel itself is closed (collapse), tabs are preserved in memory and persisted.
  - *Content embedding:* The help panel cross-references `ASCIILibrary` (9.1) for live art examples. It does not copy art content. When rendering a topic, it calls `ASCIILibrary.art(id:)` and inserts the returned text as a code block.
- **State owned:** Open tab list (`[ASCIIArtHelpTab]`), active tab ID, panel visibility (collapsed vs open). This state is persisted via `PersistenceService` (2.5) so the panel restores its tabs on relaunch.
- **Dependencies:** 9.1 ASCII Library (art content for inline examples); Foundation 2.1 InterPanelRouter (context lookup dispatch + panel open/raise routing); Foundation 2.4 UI/UX (panel slot registration, tab bar chrome); Foundation 2.5 PersistenceService (tab state persistence); Text Editor 3.3 (source of context-menu lookup trigger, `.asciiArt` editor mode).
- **Failure modes:**
  - Context lookup with no match → help panel opens/shows at the search page with the query pre-filled; user is not dropped on an empty page, and no spurious tab is created.
  - Help index missing or corrupt → panel shows a "Help not available" placeholder; context lookup silently does nothing (no crash, SR-2).
  - `@{art:uuid}` placeholder references a deleted art record → the placeholder is shown as-is (a small visual glitch, not a crash) — the caller already handled the `nil` from `ASCIILibrary.art(id:)`.
  - User opens help while the library (9.1) is still loading → the sidebar shows categories immediately (from the help index), but art examples show a "loading" spinner until `ASCIILibrary` is ready.
  - Persisted tab state references a topic that no longer exists in the index → that tab is silently dropped on restore; the panel opens with the topic index instead.
