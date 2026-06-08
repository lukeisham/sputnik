---
module: 2.4 Foundation – UI and UX
status: active
last_updated: 2026-06-08
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
└─────────────────────────────────────────────────────────────────┘

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
  - `DesignTokens` — namespace enum of static constants: colors (`SputnikColor`), fonts (`SputnikFont`), spacing (`SputnikSpacing`) <!-- assumed -->
  - `SputnikColor` — color set bridging `Color` (SwiftUI) and `NSColor` (AppKit), with light/dark variants driven by `SettingsStore.theme` <!-- assumed -->
  - `PanelID` — enum identifying each panel: `.fileTree`, `.textEditor`, `.markdownPreview`, `.htmlPreview`, `.pdfViewer`; Terminal is excluded — it is not relocatable <!-- assumed -->
  - `PanelPosition` — enum of named slots: `.left`, `.centerUpper`, `.centerLower`, `.right` <!-- assumed -->
  - `PanelLayout` — `Codable, Sendable` struct with two maps: `assignments: [PanelPosition: PanelID]` (which panel is in which slot) and `sizes: [PanelPosition: CGFloat]` (split proportions). **Component of `LayoutState`** (2.5) — not persisted standalone. See ISS-001 resolution.
  - `FocusMode` — enum: `.dev`, `.writer`, `.reader`; stored in `AppState` (2.2) <!-- assumed -->
  - `SputnikAlert` — typed error enum with associated `title: String` and `message: String`; all error dialogs are constructed from this type so presentation is consistent <!-- assumed -->
  - `DocumentTabBar` — SwiftUI view rendered above the `.centerUpper` editor slot; reads `AppState.openDocuments` and `activeDocumentID`, writes `activeDocumentID` on tab-tap, and calls an `onClose: (UUID) -> Void` callback for close gestures so the router can run the `isDirty` guard (spec 2.4.2.5 "Tabs and Windows")
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
