---
module: 2.4 Foundation – UI and UX
status: active
last_updated: 2026-06-09
---

## Purpose
Define every shared visual primitive and layout behaviour — design tokens, panel arrangement, focus modes, error dialogs — once in Foundation so all modules consume a consistent, maintainable interface.

## Diagram

```
Named slots above the terminal (panels can be placed in any slot):

┌─────────────────────────────────────────────────────────────────┐
│  Toolbar  [⊞ File Tree] [✎ Editor] [▤ Preview] [▣ PDF] [> Term]│
├──────────────┬──────────────────────┬──────────────────────────┤
│              │                      │                          │
│   .left      │   .centerUpper       │   .right                 │
│              │                      │                          │
│  (any panel) │   (any panel)        │   (any panel)            │
│              │                      │                          │
│  resizable  ◀▶  resizable          ◀▶  resizable              │
│              ├──────────────────────┴──────────────────────────┤
│              │                                                  │
│              │   .centerLower  (any panel, optional)           │
│              │                                                  │
├──────────────┴──────────────────────────────────────────────────┤
│   Terminal (7)   — always here, not part of the slot system     │
├─────────────────────────────────────────────────────────────────┤
│   StatusBarView  — 24 pt fixed height, non-resizable            │
│   [ 🛰 ]  claude-sonnet-4-6  CTX 34%  RAM 48 MB  CPU 2.1%      │
└─────────────────────────────────────────────────────────────────┘
  ↑ .overlay(alignment: .bottomTrailing) on ContentView:
  ┌──────────────┐
  │  Scratchpad  │  ← ScratchpadPanel (320×240 pt default, resizable,
  │              │    draggable; visible when AppState.scratchpadVisible)
  │  NSTextView  │
  └──────────────┘

Default slot assignment (restored from PersistenceService on launch):
  .left        → File Tree (6)
  .centerUpper → Text Editor (3)
  .right        → Markdown Preview (4) or HTML Preview (8)
  .centerLower → PDF Viewer (5)  [hidden unless a PDF is open]

Panel relocation — drag to swap:
  User drags panel title bar  →  drop target highlights on other panels
  On drop: the two panels swap PanelPosition in PanelLayout
  Terminal slot is not a valid drop target

Focus Modes (panel toggles hide/show; positions are preserved):
  Writer mode  → .left hidden, Terminal hidden
  Reader mode  → .centerUpper hidden, Terminal hidden
  Dev mode     → all panels visible (default)
```

## Technical Summary
- **Framework(s):** SwiftUI, AppKit (for `NSFont`, system icon access)
- **Key types:**
  - `DesignTokens` — namespace enum of static constants: colors (`SputnikColor`), fonts (`SputnikFont`), spacing (`SputnikSpacing`); also registers two named image assets: `SputnikMenuBar` (16 pt @1x / 32 pt @2x monochrome template for the menu-bar status item — F-1) and `SputnikLogo` (64 pt @1x / 128 pt @2x full-colour for the About window — F-1/F-2) <!-- assumed -->
  - `SputnikColor` — color set bridging `Color` (SwiftUI) and `NSColor` (AppKit), with light/dark variants driven by `SettingsStore.theme` <!-- assumed -->
  - `PanelID` — enum identifying each panel: `.fileTree`, `.textEditor`, `.markdownPreview`, `.htmlPreview`, `.pdfViewer`; Terminal is excluded — it is not relocatable <!-- assumed -->
  - `PanelPosition` — enum of named slots: `.left`, `.centerUpper`, `.centerLower`, `.right` <!-- assumed -->
  - `PanelLayout` — `Codable, Sendable` struct with two maps: `assignments: [PanelPosition: PanelID]` (which panel is in which slot) and `sizes: [PanelPosition: CGFloat]` (split proportions). **Component of `LayoutState`** (2.5) — not persisted standalone. See ISS-001 resolution.
  - `FocusMode` — enum: `.dev`, `.writer`, `.reader`; stored in `AppState` (2.2) <!-- assumed -->
  - `SputnikAlert` — typed error enum with associated `title: String` and `message: String`; all error dialogs are constructed from this type so presentation is consistent <!-- assumed -->
  - `DocumentTabBar` — SwiftUI view rendered above the `.centerUpper` editor slot; reads `AppState.openDocuments` and `activeDocumentID`, writes `activeDocumentID` on tab-tap, and calls an `onClose: (UUID) -> Void` callback for close gestures so the router can run the `isDirty` guard (spec 2.4.2.5 "Tabs and Windows")
  - `HelpTopic` — enum (`sputnik`, `markdown`, `html`, `asciiArt`, `grammar`) identifying which help panel to reveal; consumed by `AppState.requestedHelpTopic` and the Help menu
  - `AboutWindowView` — SwiftUI `View` in `2 Foundation/2.4 UI and UX/AboutWindowView.swift`; displays `SputnikLogo` (128 pt), app name, version string from `CoreSputnik`, build number, and a static credits block (hard-coded `let` string — not loaded from disk at runtime); hosted in the `Window("about")` scene in `SputnikApp`; opened via `openWindow(id: "about")` from `SputnikCommands`
  - `ScratchpadPanel` (`2 Foundation/2.4 UI and UX/ScratchpadPanel.swift`) — SwiftUI container applied as `.overlay(alignment: .bottomTrailing)` on `ContentView`; visible when `AppState.scratchpadVisible` is `true`; contains a title bar ("Scratchpad" label + close button that sets `scratchpadVisible = false`), resize handles (drag from any edge), and a drag gesture on the title bar for repositioning; default size 320×240 pt, minimum 200×120 pt; size and position persisted via `PersistenceService.scratchpadFrame`; hosts `ScratchpadTextView`
  - `ScratchpadTextView` (`2 Foundation/2.4 UI and UX/ScratchpadTextView.swift`) — `NSViewRepresentable` wrapping a plain `NSTextView`; binds to `@Binding<String>` backed by `PersistenceService.scratchpadText`; no spell-check underlines by default; `NSViewRepresentable` use is justified: `NSTextView` provides raw plain-text editing performance that `TextEditor` cannot match for an unstructured scratchpad (SW-3 — documented at call site); `NSTextViewDelegate` callbacks in `Coordinator` use `[weak self]`; becomes a consumer of `SlashCommandRegistry` when F-7 is active
  - `SlashCommandPopup` (`2 Foundation/2.4 UI and UX/SlashCommandPopup.swift`) — SwiftUI `View`; filtered `List` of `SlashCommand` rows grouped by `category`; triggered by host views when a `/` is typed at a word boundary; anchored to the cursor using `NSTextView.firstRect(forCharacterRange:actualRange:)` converted to SwiftUI coordinates; dismissed by Escape, focus loss, or confirmed selection; `onSelect: (SlashCommand) -> Void` callback returns the chosen command to the host, which replaces the `/…` token and dismisses the popup
  - `StatusBarView` (`2 Foundation/2.4 UI and UX/StatusBarView.swift`) — SwiftUI `HStack` fixed at 24 pt height at the very bottom of `ContentView` (below the Terminal strip); reads `AppState`, `SettingsStore`, and `ProcessMonitor` from the environment; segments (left to right): satellite icon with `rotationEffect` animation when `AppState.isProcessing` is true; AI model name (`SettingsStore.aiConfig.modelName`, or `"—"` if empty); context % (shown only when `aiConfig.modelName` is non-empty and `AppState.contextUsage` is non-nil); RAM and CPU % from `ProcessMonitor`; terminal model segment injected by F-8 as optional child views
  - `HelpRequest` — `Equatable Sendable` value type wrapping a `HelpTopic` `kind` and an optional `topicID: String?`; the Foundation-owned single route for help-panel navigation (ISS-008 resolved). The Help menu sets `topicID = nil` (overview); the editor's "Look Up Help" sets a resolved `topicID` so the panel scrolls to the matching topic. Written to `AppState.requestedHelpTarget`; module 9 panels observe it via `SputnikHelpPanel.navigate(to:)`. Coordinator-side wiring pattern: each coordinator singleton exposes `var onNavigate: ((HelpRequest) -> Void)?`; its panel view assigns `coordinator.onNavigate = { [weak state] request in state?.requestedHelpTarget = request }` in its `.task` body, capturing `AppState` weakly (SW-2).
- **Threading model:** All UI work is `@MainActor`. Design tokens are pure value types with no threading concerns. Panel resize and relocation events update `PanelLayout` synchronously on the main thread; the subsequent `PersistenceService` write is `Task(priority: .utility)`.
- **Data flow:** `DesignTokens` are accessed as static constants — no injection needed. `PanelLayout` is read at launch from `PersistenceService`, mutated by drag-to-swap and resize events, and written back on each change. `FocusMode` lives in `AppState`; the toolbar writes it, panels observe it via `@Environment`. Panel relocation: panel title bars expose `.onDrag` returning a `PanelID`; slot views expose `.onDrop` accepting a `PanelID`; on a valid drop the two panels' `PanelPosition` values are swapped in `PanelLayout`.
- **State owned:**
  - Design tokens — static, no runtime state.
  - `PanelLayout` — owned by `PersistenceService` (2.5); UI/UX reads and writes through it.
  - `FocusMode` — owned by `AppState` (2.2); UI/UX defines the enum and the toolbar writes it.
- **Dependencies:** `SettingsStore` (2.3) for theme; `PersistenceService` (2.5) for layout persistence; `AppState` (2.2) for focus mode.
- **Failure modes:**
  - Saved `PanelLayout` dimensions exceed current screen bounds → clamped to safe minimum/maximum on load; no crash.
  - Saved `assignments` map is missing a slot (e.g. saved before a new panel was added) → missing slots fall back to the default assignment; no crash.
  - User drops a panel onto the Terminal slot → drop is rejected; Terminal position is hardcoded and is not a valid drop target.
  - Light/dark mode change while app is running → `SputnikColor` resolves dynamically via `colorScheme` environment value; no manual refresh needed.
  - Error dialog presented with no active window → `SputnikAlert` is queued and shown once a window becomes key; never silently dropped.

## Spec Reference
> Extracted verbatim from `readme.md`:

```
  4. UI / UX
    1. Appearance
      1. Light and dark mode
      2. Dailogue boxes, tabs, toggles, sliders, buttons, icons and MacOS related finder icons
      3. Colour and fonts
    2. Functionality
      1. Adjustable top panels
      2. Panel Toggling (Focus Modes)
      3. Layout State Persistence
      4. Error Types and Messages
      5. Tabs and Windows
```
