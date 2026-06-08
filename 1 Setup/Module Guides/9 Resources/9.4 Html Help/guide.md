---
module: 9.4 Resources – HTML Help
status: draft
last_updated: 2026-06-08
---

## Purpose
Provide a comprehensive library of detailed HTML notes and tag references (based on the **HTML Living Standard**) that opens as a **dedicated panel with tabbed navigation** — analogous to how HTML Preview (8) or PDF Viewer (5) occupy their own panel slot. Each topic you navigate to (from the sidebar, search, or right-click lookup) opens as a **new tab** inside the HTML Help panel, so you can flip between multiple open references. The panel operates in two triggering modes: (1) opened directly from the menu or toolbar; and (2) context-sensitive lookup triggered by right-clicking an HTML element or attribute name in the Text Editor (3.4), which opens or raises the panel and creates a tab for the matched topic.

## Diagram

```
  ┌─ Sputnik Layout ────────────────────────────────────────────────┐
  │ ┌──────┐ ┌──────────────────────┐ ┌──────────────────────────┐  │
  │ │ File  │ │ Text Editor (3)      │ │  HTML Help Panel         │  │
  │ │ Tree  │ │  [HTML mode]         │ │  ┌──────────────────────┐│  │
  │ │ (6)   │ │                      │ │  │ ▸ <div>           ✕ ││  │
  │ │       │ │  <table>             │ │  │ ▸ <table>         ✕ ││  │
  │ │       │ │    <tr><td>hi</td>   │ │  │ ▸ class attr ──── ✕ ││  │
  │ │       │ │    </tr>             │ │  └──────────────────────┘│  │
  │ │       │ │  </table>            │ │  ┌──────┬────────────────┐│  │
  │ └──────┘ └──────────────────────┘ │  │Search│ <table>          ││  │
  │ ┌────────────────────────────────┐│  │      │                  ││  │
  │ │ Terminal (7)                   ││  │■ Elements               ││  │
  │ └────────────────────────────────┘│  │  div         border     ││  │
  └──────────────────────────────────┘  │  span    cellpadding     ││  │
                                        │  table   cellspacing     ││  │
  The HTML Help panel occupies          │    a      width          ││  │
  a panel slot in the layout, same      │  img  [ Live Demo ]     ││  │
  as HTML Preview or PDF Viewer.        └─────────────────────────┘│  │
                                        └──────────────────────────┘  │
                                                                      │
  Panel lifecycle:                                                     │
  ┌────────────┐    ┌───────────────────┐    ┌──────────────────┐     │
  │ Menu/      │───▶│ InterPanelRouter  │───▶│ Open / raise     │     │
  │ Right-click│    │ (2.1)            │    │ panel + create   │     │
  └────────────┘    │ routed to 9.4    │    │ tab for topic    │     │
                    └───────────────────┘    └──────────────────┘     │
```

### Mode Details

| Aspect | Mode 1: Menu / Toolbar | Mode 2: Context Lookup (right-click) |
|---|---|---|
| **Trigger** | Menu item `Help > HTML Help`, toolbar `?` button, or keyboard shortcut | Right-click context menu on an HTML tag or attribute in Text Editor (3.4) when editor mode is `.html` |
| **Panel action** | Opens the HTML Help panel (if closed) or raises it (if open), with the last-viewed topic or the topic index as the initial tab | Opens or raises the panel and creates a **new tab** for the matched topic; does not replace existing tabs |
| **Navigation** | Free — user browses sidebar by element category, attributes, or global attributes | Automatic — panel jumps to the best-matching topic; user can then browse normally in the same tab |
| **Tab behaviour** | Each topic clicked in the sidebar opens as a **new tab** (or re-activates an existing tab for the same topic ID). Tabs are closable (✕), reorderable by drag. The tab bar shows topic titles. | Same — the lookup result opens in a new tab. If the same topic is already open in a tab, that tab is activated instead of creating a duplicate. |
| **Panel state** | Remembers open tabs and active tab across session restarts via `PersistenceService` (2.5) | Tabs persist; closing the panel collapses it but preserves its tab state |

## Technical Summary
- **Framework(s):** SwiftUI, Foundation, WebKit (for live demos)
- **HTML Content:** Includes a built-in library of detailed HTML notes based on the **HTML Living Standard**, covering tags, attributes, structure, and best practices, with interactive code examples.
- **Key types:**
  - `HTMLHelpPanelView` — top-level SwiftUI view that registers as a panel in Foundation 2.4 (UI/UX) and manages a tab bar + the topic content area <!-- assumed -->
  - `HTMLHelpTabView` — individual tab content wrapping `HTMLHelpContentView` for a single topic. Tabs are identified by topic ID. <!-- assumed -->
  - `HTMLHelpContentView` — the content area inside a tab: sidebar `List` of topics (Elements, Attributes, Global Attributes, Events, Best Practices) and a detail `ScrollView` rendering help content. Some topics include a live demo panel using a small `WKWebView` <!-- assumed -->
  - `HTMLHelpTab` — value type: `id: UUID` (topic ID), `title: String`, `dateOpened: Date` (for ordering) <!-- assumed -->
  - `HTMLHelpPanelViewModel` — `@MainActor @Observable` class owning the open-tab list, active tab ID, and panel visibility; saved/restored via `PersistenceService` (2.5) <!-- assumed -->
  - `HTMLHelpContent` — `Codable` value type: `id: UUID`, `title: String`, `category: String` (element / attribute / global / event / guide), `body: String` (markdown with optional `@{demo:html}` placeholders), `relatedTopics: [UUID]`, `exampleHTML: String?` (snippet rendered in the live demo panel) <!-- assumed -->
  - `HTMLHelpIndex` — loaded from `9 Resources/HTMLHelp/index.json`; supports full-text search across title, body, and category <!-- assumed -->
  - `HTMLHelpCoordinator` — receives context-lookup requests from `InterPanelRouter` (2.1); maps the query to a help topic; opens/creates a tab for the result <!-- assumed -->
- **Content source:** Help topics live as `.md` files in `9 Resources/HTMLHelp/`, organised into subdirectories: `elements/`, `attributes/`, `globals/`, `events/`, `guides/`. An `index.json` at the root lists every topic with metadata. Topics that include `exampleHTML` are rendered live in a small `WKWebView` demo panel within the detail view.
- **Threading model:** Index loaded once on `Task(priority: .userInitiated)` and cached. Topic content loaded on demand. `WKWebView` demo panel content is loaded on `@MainActor` (WebKit requirement).
- **Data flow:**
  - *Panel open:* Menu/toolbar trigger → `InterPanelRouter` (2.1) routes to the HTML Help panel via Foundation 2.4's panel registry → panel opens in its assigned layout slot → `HTMLHelpPanelViewModel` restores tab state from `PersistenceService` → if no saved tabs, creates an initial index tab.
  - *Sidebar click:* User clicks a topic in the sidebar → `HTMLHelpPanelViewModel.openTab(topicID:)` — if a tab for this topic already exists, activate it; otherwise create a new tab, load the `.md` file, render body as styled text, append to tab list.
  - *Context lookup:* User right-clicks in editor (3.4) → context menu analyses cursor context: if cursor is on a `<tagname` it extracts the tag name; if on an `attr="..."` it extracts the attribute name → `InterPanelRouter` sends `{source: .editor, query: <tag/attribute>, fileType: .html, cursorContext: <raw-prefix>}` → `HTMLHelpCoordinator` searches index → calls `HTMLHelpPanelViewModel.openTab(topicID:)` which opens/raises the panel and activates/creates the tab. Falls back to search results page with query pre-filled if no match.
  - *Tab close:* User clicks ✕ on a tab → `HTMLHelpPanelViewModel.closeTab(tabID:)` — if it was the last tab, show the topic index; if the panel itself is closed (collapse), tabs are preserved.
  - *Live demos:* `exampleHTML` snippets are rendered in a sandboxed `WKWebView` that disables all navigation and script execution (static rendering only). The view is small (~200 px tall) and embedded in the detail scroll view. Each tab has its own `WKWebView` instance for the live demo if applicable.
- **State owned:** Open tab list (`[HTMLHelpTab]`), active tab ID, panel visibility (collapsed vs open). This state is persisted via `PersistenceService` (2.5) so the panel restores its tabs on relaunch.
- **Dependencies:** Foundation 2.1 InterPanelRouter (context lookup + panel open/raise routing); Foundation 2.4 UI/UX (panel slot registration, tab bar chrome); Foundation 2.5 PersistenceService (tab state persistence); Text Editor 3.4 (context-menu trigger, `.html` editor mode); WebKit (live demo panel, sandboxed).
- **Failure modes:**
  - Context lookup query resolves to nothing → help panel opens/shows at the search results page with query pre-filled; no spurious tab is created.
  - Help index missing or corrupt → panel shows a "Help not available" placeholder; context lookup does nothing (no crash, SR-2).
  - `WKWebView` fails to render a live demo (sandbox, memory) → the demo area shows a "Demo unavailable" note; the topic's text content remains fully accessible.
  - Cross-referenced topic missing → the link renders as styled text with a "Topic not found" indication; no crash.
  - Persisted tab state references a topic that no longer exists in the index → that tab is silently dropped on restore; the panel opens with the topic index instead.
  - Multiple tabs each with their own `WKWebView` live demos → bounded by the number of tabs the user opens; each `WKWebView` is deallocated when its tab is closed, keeping total RAM in check (SR-3).
