---
module: 2.0 App Overview
status: active
last_updated: 2026-06-09
---

## Purpose

Sputnik is a native macOS development environment that coordinates six concurrent panels — File Tree, Text Editor, Markdown Preview, PDF Viewer, HTML Preview, and Terminal — within a unified, crash-resistant, memory-efficient, minimalist window.

---

## Diagram

```
╔══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╗
║ ●  ○  ○   Sputnik          Sputnik   File   Edit   View   Window   Help                              — □ ×             ║
╠══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╣
║  WINDOW TAB BAR  (DocumentTabBar — Module 2.4)                                                                           ║
║                                                                                                                          ║
║   ┌─────────────────┐  ┏━━━━━━━━━━━━━━━━━━━━━━━┓  ┌──────────────────────┐  ┌──────────────────┐  ┌─┐                 ║
║   │  📄 readme.md ×  │  ┃ ◉ 📝 guide.md      × ┃  │  🌐 index.html     × │  │  📕 spec.pdf   × │  │+│                 ║
║   └─────────────────┘  ┗━━━━━━━━━━━━━━━━━━━━━━━┛  └──────────────────────┘  └──────────────────┘  └─┘                 ║
║        inactive                  ▲ ACTIVE                inactive                  inactive         new                 ║
║                                  │                                                                                       ║
║                    ┌─────────────┴──────────────────────────────────────┐                                               ║
║                    │  active tab drives both centre panels below  (↓↓)  │                                               ║
║                    └────────────────────────────────────────────────────┘                                               ║
╠════════════════════╦═════════════════════════════════════════════════════╦════════════════════════════════════════════════╣
║                    ║                                                     ║                                               ║
║  LEFT SLOT         ║  ╔══ ACTIVE PAIR: guide.md  [Markdown mode] ══════╗ ║  RIGHT SLOT                                  ║
║  Module 6          ║  ║                                                 ║ ║  Module 5 — PDF Viewer                       ║
║  File Tree         ║  ║  CENTRE UPPER — Text Editor  (Module 3)        ║ ║  ──────────────────────────────────          ║
║  ────────────────  ║  ║  ─────────────────────────────────────────     ║ ║                                               ║
║                    ║  ║   1  │ ---                                      ║ ║  ┌────────────────────────────────────┐      ║
║  📂 App_Sputnik/   ║  ║   2  │ module: 2.0 App Overview                ║ ║  │                                    │      ║
║  ├── 📂 2 Found.   ║  ║   3  │ status: draft                           ║ ║  │        Sputnik Design Doc          │      ║
║  │   ├── 📄 App..  ║  ║   4  │ last_updated: 2026-06-08                ║ ║  │        ────────────────────        │      ║
║  │   ├── 📄 Con..  ║  ║   5  │                                         ║ ║  │                                    │      ║
║  │   └── 📄 Lay..  ║  ║   6  │ ## Purpose                              ║ ║  │  1. Introduction .............. 1  │      ║
║  ├── 📂 3 Editor   ║  ║   7  │                                         ║ ║  │  2. Architecture .............. 4  │      ║
║  ├── 📂 4 Mkdn.    ║  ║   8  │ Sputnik is a native macOS              ║ ║  │  3. Modules ................... 8  │      ║
║  ├── 📂 5 PDF      ║  ║   9  │ development environment...              ║ ║  │                                    │      ║
║  ├── 📂 7 Term.    ║  ║   ·  │                                         ║ ║  │  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │      ║
║  └── 📂 8 HTML     ║  ║   ·  │  ░░ inline suggestion ░░░░░░░░░░░░░░   ║ ║  │  ░░░░░░  page content  ░░░░░░░░   │      ║
║                    ║  ║                                                 ║ ║  │  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │      ║
║  ────────────────  ║  ╠═════════════════════════════════════════════════╣ ║  │                                    │      ║
║  Right-click menu: ║  ║  CENTRE LOWER — Markdown Preview  (Module 4)   ║ ║  │  [◀ Prev]   Page 1 / 24  [Next ▶] │      ║
║  ┌──────────────┐  ║  ║  [synced to active tab: guide.md]              ║ ║  │                                    │      ║
║  │ 📄 New File  │  ║  ║  ─────────────────────────────────────────     ║ ║  ├────────────────────────────────────┤      ║
║  │ 📂 New Folder│  ║  ║                                                 ║ ║  │ TOC Sidebar                        │      ║
║  │    Rename    │  ║  ║  # 2.0 App Overview                            ║ ║  │ ▸ 1. Introduction                  │      ║
║  │    Trash     │  ║  ║                                                 ║ ║  │ ▸ 2. Architecture                  │      ║
║  └──────────────┘  ║  ║  Sputnik is a native macOS development         ║ ║  │ ▸ 3. Modules                       │      ║
║                    ║  ║  environment that coordinates **six**           ║ ║  └────────────────────────────────────┘      ║
║  File icons:       ║  ║  concurrent views within a unified,            ║ ║                                               ║
║  📂 folder open    ║  ║  crash-resistant, memory-efficient layout.      ║ ║                                               ║
║  📁 folder closed  ║  ║                                                 ║ ║                                               ║
║  📄 text/generic   ║  ║  ## Technical Summary                          ║ ║                                               ║
║  📝 markdown .md   ║  ║  - **Framework(s):** SwiftUI, AppKit           ║ ║                                               ║
║  🌐 html .html     ║  ║  - **Key types:** ContentView, AppState...     ║ ║                                               ║
║  📕 pdf .pdf       ║  ║                                                 ║ ║                                               ║
║  🔤 swift .swift   ║  ╚═════════════════════════════════════════════════╝ ║                                               ║
║                    ║                                                     ║                                               ║
╠════════════════════╩═════════════════════════════════════════════════════╩════════════════════════════════════════════════╣
║  TERMINAL STRIP — Module 7  (pinned at bottom; cannot be relocated)                                                      ║
║  ┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  ║
║  │  [zsh ×]  [zsh ×]  [+]                                                                      [↑ Expand]  [Clear]    │  ║
║  ├────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤  ║
║  │  App_Sputnik % swift build                                                                                          │  ║
║  │  Build complete!  (0.43s)                                                                                           │  ║
║  │  App_Sputnik % █                                                                                                    │  ║
║  └────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝


ACTIVE PAIR — how the tab bar drives the centre column:

  Each open document tab owns a DocumentSession (file URL + mode + dirty flag).
  The active tab's session is the single source of truth for BOTH centre panels:

  ┌────────────────────────────────────────────────────────────────────────────────────────────┐
  │  TAB BAR                                                                                   │
  │  [ readme.md ]  [━━━ guide.md ◉ ━━━]  [ index.html ]  [ spec.pdf ]  [+]                  │
  │                          │                                                                 │
  │            ┌─────────────┴──────────────────────┐                                         │
  │            │  DocumentSession: guide.md          │                                         │
  │            │  mode: .markdown   dirty: false     │                                         │
  │            └──────────┬──────────────────────────┘                                         │
  │                       │                                                                    │
  │          ┌────────────┴────────────┐                                                       │
  │          ▼                         ▼                                                       │
  │  ┌───────────────────┐   ┌─────────────────────────┐                                      │
  │  │  Text Editor      │   │  Markdown Preview        │                                      │
  │  │  (Module 3)       │   │  (Module 4)              │                                      │
  │  │  edits content    │   │  renders content live    │                                      │
  │  │  of guide.md      │   │  from the same session   │                                      │
  │  └───────────────────┘   └─────────────────────────┘                                      │
  └────────────────────────────────────────────────────────────────────────────────────────────┘

  Mode determines which lower panel is active:
  ┌─────────────┬──────────────────────────────────────────┬───────────────────────────────────┐
  │  File type  │  Centre Upper                            │  Centre Lower                     │
  ├─────────────┼──────────────────────────────────────────┼───────────────────────────────────┤
  │  .md        │  Text Editor  (Module 3)                 │  Markdown Preview  (Module 4)     │
  │  .html      │  Text Editor  (Module 3)                 │  HTML Preview      (Module 8)     │
  │  .txt/.swift│  Text Editor  (Module 3)                 │  (lower panel hidden)             │
  │  .pdf       │  PDF Viewer   (Module 5)  — read only    │  (lower panel hidden)             │
  └─────────────┴──────────────────────────────────────────┴───────────────────────────────────┘


PANEL SLOT MAP (relocatable except Terminal):

  ┌──────────────┬─────────────────────────────────────────┬──────────────────────────────────┐
  │  LEFT SLOT   │         CENTRE UPPER SLOT               │         RIGHT SLOT               │
  │  (Module 6)  │         (Module 3 or 5)                 │      (Module 4 / 5 / 8)          │
  │  File Tree   │  Text Editor  /  PDF Viewer             │  PDF Viewer  /  Preview          │
  │              ├─────────────────────────────────────────┤                                  │
  │  (any panel  │         CENTRE LOWER SLOT               │                                  │
  │   can move   │         (Module 4 or 8)                 │                                  │
  │   here via   │  Markdown Preview  /  HTML Preview      │                                  │
  │   drag-drop) │  (hidden when active file has no pair)  │                                  │
  ├──────────────┴─────────────────────────────────────────┴──────────────────────────────────┤
  │  TERMINAL STRIP — Module 7 — PINNED, NOT RELOCATABLE                                      │
  └───────────────────────────────────────────────────────────────────────────────────────────┘


FOCUS / TOGGLE MODES  (View menu):

  Default layout (all panels visible):
  ┌──────────────┬────────────────────────────────────────┬─────────────────────────────────┐
  │              │  [━guide.md◉━] [readme] [index] [+]   │                                 │
  │  File Tree   │  ──────────────────────────────────    │  PDF Viewer                     │
  │              │  Text Editor  (guide.md)               │                                 │
  │              │  ──────────────────────────────────    │                                 │
  │              │  Markdown Preview  (guide.md)          │                                 │
  ├──────────────┴────────────────────────────────────────┴─────────────────────────────────┤
  │  Terminal                                                                                │
  └──────────────────────────────────────────────────────────────────────────────────────────┘

  Focus: Editor  (left + right panels hidden):
  ┌────────────────────────────────────────────────────────────────────────────────────────┐
  │  [━guide.md◉━]  [readme]  [index]  [+]                                                 │
  │  ──────────────────────────────────────────────────────────────────────────────────    │
  │  Full-width Text Editor  (guide.md)                                                    │
  │  ──────────────────────────────────────────────────────────────────────────────────    │
  │  Full-width Markdown Preview  (guide.md)                                               │
  ├────────────────────────────────────────────────────────────────────────────────────────┤
  │  Terminal                                                                               │
  └────────────────────────────────────────────────────────────────────────────────────────┘

  Focus: Reader  (left panel + editor hidden, preview fills):
  ┌────────────────────────────────────────────────────────────────────────────────────────┐
  │  Full-width Markdown / HTML Preview  or  PDF Viewer                                    │
  │                                                                                        │
  ├────────────────────────────────────────────────────────────────────────────────────────┤
  │  Terminal                                                                               │
  └────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Menu Bar

```
 Sputnik   File   Edit   View   Window   Help
 ───────   ────   ────   ────   ──────   ────

┌─────────────────────────┐
│ Sputnik                 │
├─────────────────────────┤
│ About Sputnik           │
├─────────────────────────┤
│ Settings...        ⌘,   │
├─────────────────────────┤
│ Hide Sputnik       ⌘H   │
│ Hide Others       ⌥⌘H   │
│ Show All                │
├─────────────────────────┤
│ Quit Sputnik       ⌘Q   │
└─────────────────────────┘

         ┌──────────────────────────────┐
         │ File                         │
         ├──────────────────────────────┤
         │ New Tab              ⌘T      │
         │ New Window           ⇧⌘N     │
         ├──────────────────────────────┤
         │ Open...              ⌘O      │
         │ Open Recent        ▶         │
         │  ├ guide.md                  │
         │  ├ readme.md                 │
         │  └ Clear Menu                │
         ├──────────────────────────────┤
         │ Close Tab            ⌘W      │
         │ Close Window         ⇧⌘W     │
         ├──────────────────────────────┤
         │ Save                 ⌘S      │
         │ Save As...           ⇧⌘S     │
         ├──────────────────────────────┤
         │ Print...             ⌘P      │
         └──────────────────────────────┘

                  ┌───────────────────────────────┐
                  │ Edit                          │
                  ├───────────────────────────────┤
                  │ Undo                  ⌘Z      │
                  │ Redo                  ⇧⌘Z     │
                  ├───────────────────────────────┤
                  │ Cut                   ⌘X      │
                  │ Copy                  ⌘C      │
                  │ Paste                 ⌘V      │
                  │ Select All            ⌘A      │
                  ├───────────────────────────────┤
                  │ Find                ▶         │
                  │  ├ Find...            ⌘F      │
                  │  ├ Find and Replace   ⌥⌘F     │
                  │  ├ Find Next          ⌘G      │
                  │  └ Find Previous      ⇧⌘G     │
                  ├───────────────────────────────┤
                  │ Spelling and Grammar▶         │
                  │  ├ Check Now          ⌘;      │
                  │  ├ Check While Typing         │
                  │  └ Show Corrections           │
                  └───────────────────────────────┘

                           ┌──────────────────────────────────┐
                           │ View                             │
                           ├──────────────────────────────────┤
                           │ Toggle File Tree         ⌥⌘1    │
                           │ Toggle Preview           ⌥⌘2    │
                           │ Toggle Right Panel       ⌥⌘3    │
                           │ Toggle Terminal          ⌥⌘4    │
                           ├──────────────────────────────────┤
                           │ Focus: Editor            ⌃⌘E    │
                           │ Focus: Reader            ⌃⌘R    │
                           │ Restore Default Layout   ⌃⌘0    │
                           ├──────────────────────────────────┤
                           │ Appearance               ▶       │
                           │  ├ Light Mode                    │
                           │  ├ Dark Mode                     │
                           │  └ Use System Setting  ✓        │
                           └──────────────────────────────────┘

                                    ┌──────────────────────────────┐
                                    │ Window                       │
                                    ├──────────────────────────────┤
                                    │ Minimize              ⌘M     │
                                    │ Zoom                         │
                                    ├──────────────────────────────┤
                                    │ Move Tab to New Window       │
                                    │ Merge All Windows            │
                                    ├──────────────────────────────┤
                                    │ — open documents ——————————  │
                                    │   guide.md              ✓   │
                                    │   readme.md                  │
                                    │   index.html                 │
                                    └──────────────────────────────┘

                                             ┌──────────────────────┐
                                             │ Help                 │
                                             ├──────────────────────┤
                                             │ Sputnik Help   ⌘?    │
                                             ├──────────────────────┤
                                             │ Markdown Help        │
                                             │ HTML Help            │
                                             │ ASCII Art Help       │
                                             │ Grammar Help         │
                                             ├──────────────────────┤
                                             │ Release Notes        │
                                             │ Report an Issue...   │
                                             └──────────────────────┘
```

---

## Technical Summary

- **Framework(s):** SwiftUI (layout, state binding, `CommandMenu` for the menu bar), AppKit via `NSViewRepresentable` (editor, terminal, PDF), Foundation
- **Key types:**
  - `ContentView` — root SwiftUI view; wires the three-column `HStack` + pinned Terminal `VStack`; receives `windowState: WindowState` and `router: InterPanelRouter` at init; injects `windowState` into the environment for child panels
  - `AppState` — `@Observable @MainActor` class, **window coordinator**; owns a dictionary of `WindowState` instances, tracks the active window via `@FocusedValue`, and provides computed pass-throughs that delegate to the active window
  - `WindowState` — `@Observable @MainActor` class, one per open window; holds workspace directory, open documents, active document ID, layout, scratchpad, help routing, AI state, and terminal manager reference
  - `DocumentSession` — per-tab model: file URL, dirty flag, mode (`.text` / `.markdown` / `.html` / `.pdf`); stored on `WindowState.openDocuments`
  - `DocumentTabBar` — SwiftUI tab strip spanning the full window width; maps to `windowState.openDocuments`
  - `PanelPosition` — enum (`left`, `centerUpper`, `centerLower`, `right`)
  - `LayoutState` — persisted struct holding panel visibility bitmask, layout preset, and focus mode (stored per-window on `WindowState`)
  - `InterPanelRouter` — routes open-file events from File Tree → Editor, and sync events Editor → Previews
  - `SputnikCommands` — SwiftUI `Commands` struct wiring all menu bar items to `AppState` actions; uses `openWindow` environment action for window creation
  - `SettingsStore` — `@Observable` model backing the Settings panel; settings are global (not per-window)
- **Multi-window menu commands:**
  - **File ▸ New Window (⇧⌘N):** calls `appState.createWindow()` and `openWindow(id: "main", value: ws.id)` — no longer a stub.
  - **Window ▸ Move Tab to New Window:** detaches the active document from the current `WindowState`, creates a new window, moves the session there.
  - **Window ▸ Merge All Windows:** collects all tabs from all windows into the active window, closes other windows and kills their terminals.
- **Threading model:** all `AppState` and `WindowState` mutations on `@MainActor`; file-system watching and I/O on background `Task`s; Terminal PTY I/O on a dedicated actor
- **Data flow:** File Tree selection → `InterPanelRouter.open(_:)` → `appState.openDocument(url:)` (delegates to active `WindowState.openDocuments`) → `DocumentTabBar` observes `windowState.openDocuments` → centre editor receives `windowState.activeDocument` → previews observe `DocumentSession.content`
- **State owned:** `AppState` owns the window registry and global state (Supporting AI usage, recent files); `WindowState` owns per-window state; each module owns its own view-local scroll and selection state
- **Dependencies:** All other modules (3–8) depend on Foundation; Foundation has no upstream module dependencies
- **Failure modes:** missing file at open → `InterPanelRouter` emits `.fileNotFound` error; corrupted `LayoutState` on disk → reset to default silently; Terminal PTY spawn failure → error shown in terminal strip with retry button; window close while terminal running → `AppDelegate` collects and kills all PTYs across all windows

---

## Spec Reference

> Extracted from `readme.md` — the original bullet points for the app:

```
Sputnik is a native macOS development environment that coordinates six concurrent views —
a Project File Tree, a Text Editor (Text, Markdown, ASCII art and HTML), a Markdown preview
synchronized to the editor, a PDF viewer, a HTML preview also synchronized to the editor,
and an integrated Zsh Terminal — within a unified, crash-resistant, memory-efficient
minimalist layout.

2. FOUNDATION = fundamental functions and user interfaces
  1. Inter-panel communication
  2. Global State Management
  3. Settings
  4. UI / UX
     1. Appearance: light/dark mode, dialogs, tabs, toggles, sliders, buttons, icons
     2. Functionality: adjustable panels, panel toggling (Focus Modes), layout state
        persistence, error types, tabs and windows, panel relocation
```
