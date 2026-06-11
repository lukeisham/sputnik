---
module: 2.0 App Overview
status: active
last_updated: 2026-06-11
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

## Menu Item Reference

### Standard macOS items — Sputnik behaviour

- **About Sputnik** — opens a dedicated `"about"` SwiftUI window (id registered in `SputnikApp`); does not use the default `NSApp` About panel.
- **Settings… ⌘,** — sends the standard `showSettingsWindow:` action to `NSApp`; opens the SwiftUI `Settings` scene.
- **Hide Sputnik ⌘H** — calls `NSApp.hide(nil)`; standard macOS hide.
- **Hide Others ⌥⌘H** — calls `NSApp.hideOtherApplications(nil)`.
- **Show All** — calls `NSApp.unhideAllApplications(nil)`.
- **Quit Sputnik ⌘Q** — calls `NSApp.terminate(nil)`; `AppDelegate.applicationWillTerminate` kills all PTYs before exit.
- **New Tab ⌘T** — calls `appState.newUntitledDocument()`; appends an untitled `DocumentSession` to the active `WindowState`.
- **Open… ⌘O** — presents `NSOpenPanel` (single file, no directories); on confirmation calls `appState.openDocument(url:)`.
- **Open Recent ▶** — lists `appState.recentFiles` (URLs); selecting one calls `appState.openDocument(url:)`; "Clear Menu" calls `appState.clearRecentFiles()`.
- **Close Tab ⌘W** — calls `appState.closeDocument(id:)` on the active document ID; if it's the last tab the window stays open with an empty state.
- **Close Window ⇧⌘W** — calls `NSApp.keyWindow?.close()`; `AppDelegate` handles PTY cleanup on window close.
- **Save ⌘S** — calls `appState.editorCommandHandler?.save()`; disabled when no document is open.
- **Save As… ⇧⌘S** — presents `NSSavePanel` pre-filled with the current filename; on confirmation calls `editorCommandHandler?.saveAs(to:)`; disabled when no document is open.
- **Print… ⌘P** — sends `NSDocument.printDocument(_:)` to the responder chain.
- **Undo ⌘Z / Redo ⇧⌘Z** — forwards `undo:` / `redo:` selectors to the responder chain (handled by `NSTextView` inside the editor).
- **Cut ⌘X / Copy ⌘C / Paste ⌘V / Select All ⌘A** — forwards the standard `NSText` selectors to the responder chain.
- **Find… ⌘F / Find and Replace… ⌥⌘F / Find Next ⌘G / Find Previous ⇧⌘G** — forwards `performFindPanelAction(_:)` to `NSTextView`; the native find bar appears inside the editor.
- **Check Spelling Now ⌘;** — forwards `checkSpelling(_:)` to `NSTextView`.
- **Check While Typing (toggle)** — reads/writes `settings.spellCheckEnabled` via `SettingsStore`; live spell-check underlines update immediately.
- **Grammar Checking (toggle)** — reads/writes `settings.grammarCheckEnabled`.
- **Minimize ⌘M** — calls `NSApp.keyWindow?.miniaturize(nil)`.
- **Zoom** — calls `NSApp.keyWindow?.zoom(nil)`; toggles between user-set size and macOS-computed ideal size.

---

### Sputnik-unique items

- **New Window ⇧⌘N** — calls `appState.createWindow()` to allocate a new `WindowState`, then calls `openWindow(id: "main", value: ws.id)` to open a fully independent Sputnik window with its own file tree, editor, previews, and terminal.
- **Render as HTML ⌥⌘P** — calls `editorCommandHandler?.renderAsHTML()`; converts the active Markdown document to an HTML file and opens it in the HTML Preview panel; disabled when no document is open.
- **Toggle File Tree ⌥⌘1** — calls `appState.toggleVisibility(.left)`; shows or hides the left File Tree panel without affecting other panels.
- **Toggle Preview ⌥⌘2** — calls `appState.toggleVisibility(.centerLower)`; shows or hides the centre-lower Markdown/HTML Preview panel.
- **Toggle Right Panel ⌥⌘3** — calls `appState.toggleVisibility(.right)`; shows or hides the right PDF Viewer / Preview panel.
- **Toggle Terminal ⌥⌘4** — calls `appState.toggleTerminal()`; shows or hides the pinned Terminal strip at the bottom of the window.
- **Scratchpad ⇧⌘K** — toggles `appState.scratchpadVisible`; a floating overlay scratchpad that persists independently of the open document.
- **Focus: Editor ⌃⌘E** — sets left and right panel visibility to `false`, centre-upper to `true`, centre-lower to `false`; expands the editor to full window width.
- **Focus: Reader ⌃⌘R** — hides left, right, and centre-upper panels; expands the preview (Markdown, HTML, or PDF) to fill the window.
- **Restore Default Layout ⌃⌘0** — calls `appState.restoreDefaultLayout()`; returns all panels to the default three-column arrangement.
- **Appearance ▶ (Light / Dark / Use System Setting)** — calls `settings.setTheme(.light / .dark / .system)`; overrides the per-app colour scheme independently of macOS system appearance.
- **ASCII Studio ⌥⌘A** — calls `editorCommandHandler?.showASCIIStudio()`; opens the ASCII art creation panel for the active document; disabled when no document is open.
- **Writing Assistance ▶** — per-language AI writing feature toggles backed by `SettingsStore.writingAssist`:
  - **All On / All Off** — calls `settings.setWritingAssistMatrix(.allOn() / .allOff())`; bulk-enables or disables every writing feature at once.
  - **Spelling ▶** — Instant Correct (auto-fixes typos on space) and Auto-Complete (inline word suggestions).
  - **Grammar ▶** — Instant Correct and More Context (sends surrounding sentences for richer grammar analysis).
  - **Markdown ▶** — Auto-Complete (suggests Markdown syntax) and More Context.
  - **HTML ▶** — Auto-Complete (tag and attribute suggestions) and More Context.
  - **ASCII Art ▶** — Auto-Complete (suggests shapes from the ASCII library).
- **Move Tab to New Window** — routes through `router.moveActiveTabToNewWindow()`; the router fires a dirty-tab guard (ISS-020) before detaching the `DocumentSession` and opening a new window via `openWindow`.
- **Merge All Windows** — iterates `appState.orderedWindowIDs`; moves all `DocumentSession`s into the active window (deduplicating by URL), closes each source `NSWindow` by matching its `identifier` to the `WindowState` UUID (ISS-018), then asynchronously kills all terminal PTYs from the closed windows.
- **Sputnik Help ⌘?** — sets `appState.requestedHelpTopic = .sputnik`; the help overlay panel observes this and opens the built-in Sputnik guide.
- **Markdown Help** — sets `appState.requestedHelpTopic = .markdown`; opens the Markdown reference guide.
- **HTML Help** — sets `appState.requestedHelpTopic = .html`; opens the HTML reference guide.
- **ASCII Art Help** — sets `appState.requestedHelpTopic = .asciiArt`; opens the ASCII Art reference guide.
- **Grammar Help** — sets `appState.requestedHelpTopic = .grammar`; opens the Grammar reference guide.
- **Release Notes** — currently disabled (no URL assigned yet).
- **Report an Issue…** — constructs a `mailto:` URL with a pre-filled subject and calls `NSWorkspace.shared.open(_:)`; opens the user's default mail client addressed to the developer.

---

## 2.7.4 Error & Performance Utilities

Four utility types added during the Foundation Polish phase live under `2.7 Utilities/`:

- **`ErrorReporting`** (`actor`) — Centralized non-fatal error logger. Writes to `os_log` and an in-memory ring buffer (1,000 entries). Thread-safe via actor isolation; call with `await ErrorReporting.shared.log(...)` or `report(...)` from any module (see [2.7 Utilities guide](2.7%20Utilities/guide.md) for full API).
- **`PreviewImageCache`** (`actor`) — Thread-safe `NSCache`-backed image store with generation-based invalidation and auto-downsampling to 2048 px max dimension. Use `PreviewImageCache.shared.image(for:loader:)` from preview panels to avoid redundant image decoding and reduce peak RAM (SR-3).
- **`RenderThrottle`** (`final class`) — Generation-based render coalescer wrapping `DebounceTimer`. Prevents redundant re-renders when input arrives faster than the render can complete (e.g., fast typing). Configured with a 0.1 s debounce by default. Use `throttle(render:)` in preview view-models (SR-4).
- **`TestingSupport`** — Mock implementations (`MockInterPanelRouter`, `MockAppState`, `MockWindowState`) for unit-testing module logic without setting up real panels or state. See the test file at `2 Foundation/Tests/FoundationModuleTests.swift`.

See the [2.7 Utilities guide](2.7%20Utilities/guide.md) for detailed API documentation, threading model, and known consumers.

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
