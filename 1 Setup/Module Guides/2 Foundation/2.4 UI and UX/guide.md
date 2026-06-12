---
module: 2.4 Foundation – UI and UX
status: active
last_updated: 2026-06-12
last_verified: 2026-06-12
open_issues: none
---

## Purpose
Define every shared visual primitive and layout behaviour — design tokens, dynamic panel arrangement, drag-to-reorder, scrollable tab bar, render-mode toggle, error dialogs — once in Foundation so all modules consume a consistent, maintainable interface.

## Diagram

```
Dynamic columns above the terminal (ordered list of PanelColumn):

Default three-column layout:
┌──────────┬──────────────────────────────┬─────────────────────────┐
│          │                              │                         │
│ .fileTree│    .textEditor               │ .markdownPreview        │
│ (20%)    │    (45%)                     │ (35%)                   │
│          │                              │                         │
│  resizable  ◀▬drop zone▬▶  resizable    ◀▬drop zone▬▶  resizable │
├──────────┴──────────────────────────────┴─────────────────────────┤
│   Terminal (7) — always here, full-width bottom strip              │
├────────────────────────────────────────────────────────────────────┤
│   DockedScratchpadPanel (docked to right of Terminal)              │
│   [⇧⌘K toggles]  width persisted via UserDefaults (200…600 pt)    │
├────────────────────────────────────────────────────────────────────┤
│   StatusBarView — 24 pt fixed height, non-resizable               │
│   [ 🛰 ]  deepseek-chat  claude-sonnet-4-6  CTX 34%  RAM 48 MB  CPU 2.1%     │
└────────────────────────────────────────────────────────────────────┘

Column creation:
- Drag a column title bar into a between-column drop zone → new column appears
- Drag a column title bar onto another column → becomes a tab in the target column
- File Tree constraint: .fileTree column can only exist at index 0 or last

Column removal:
- ✕ button on title bar removes the column
- Removing the last column restores the default three-column layout

Multi-tab columns:
- More than one document in a column → scrollable tab bar appears below title bar
- Click tab to switch visible document
- Active text editor column has a 2 pt solid accent border
- Active-pair preview (matching-doc MD/HTML) has a 1 pt dashed accent border
```

## Source Files
| File | Responsibility |
|---|---|
| `DesignTokens.swift` | Enum namespaces: `SputnikSpacing` (xs/sm/md/lg/xl), `SputnikFont` (caption/body/headline/title pt sizes) |
| `SputnikColor.swift` | `enum` — static `Color`/`NSColor` properties for backgrounds, text, accents, selection, separators |
| `PanelID.swift` | `Codable Sendable` enum — `fileTree`, `textEditor`, `markdownPreview`, `htmlPreview`, `pdfViewer`, plus help panel IDs |
| `DynamicPanelLayout.swift` | `Codable Sendable` struct — ordered list of `PanelColumn`s; column role computation, File Tree constraint, render-mode toggle, column mutations |
| `PanelColumn.swift` | `Codable Sendable` struct — single column: stable UUID, renderMode, tabbed document IDs, proportional width |
| `PanelColumnView.swift` | SwiftUI view — title bar, tab bar, role border, `.onDrag`/`.onDrop`, drag-to-tab creation, close button |
| `ColumnDropDelegate.swift` | `DropDelegate` — decode UUID from item provider, call `moveColumn` to reposition columns on drop |
| `DropZoneView.swift` | SwiftUI view — 8 pt invisible between-column drop zone with blue hover highlight; calls `addColumn` on drop |
| `SputnikAlert.swift` | `Error Sendable Equatable` enum — typed error cases for dialog presentation |
| `SputnikError.swift` | `Error Sendable` enum — `hardwareAccessDenied`, `processLaunchFailed`, `ptyWriteFailed` |
| `HelpTopic.swift` | `Codable Sendable CaseIterable Identifiable` enum — `.sputnik`, `.markdown`, `.html`, `.asciiArt`, `.grammar` |
| `DocumentTabBar.swift` | SwiftUI tab strip — reads `openDocuments`/`activeDocumentID`, writes `activeDocumentID`, drag-to-reorder (ISS-019) |
| `AboutWindowView.swift` | SwiftUI About window — Sputnik logo, version, build, credits |
| `DockedScratchpadPanel.swift` | SwiftUI panel — docked beside Terminal, resizable horizontally, persisted width |
| `ScratchpadTextView.swift` | `NSViewRepresentable` wrapping `NSTextView` (SW-3) |
| `SlashCommandPopup.swift` | SwiftUI popup — filtered slash-command list anchored to cursor |
| `StatusBarView.swift` | SwiftUI bottom bar — satellite, AI segments, RAM, CPU |
| `DebounceStepPicker.swift` | Reusable SwiftUI `Picker` for `AutoCompleteDebounceStep` |

## Technical Summary
- **Framework(s):** SwiftUI, AppKit (for `NSFont`, system icon access)
- **Key types:**
  - `SputnikSpacing` / `SputnikFont` / `SputnikColor` — design token enums; colours bridge `Color` (SwiftUI) and `NSColor` (AppKit)
  - `PanelID` — `Codable Sendable` enum identifying panels; Terminal excluded (not relocatable)
  - `DynamicPanelLayout` — `Codable Sendable` struct; ordered `columns` array; default three-column layout; File Tree edge constraint; column role computation (`active`, `activePair`, `viewOnly`); render-mode toggle (`toggleRenderMode`, `revertToggleIfNeeded`)
  - `PanelColumn` — `Codable Sendable Identifiable` struct; stable `id` (UUID), `renderMode`, `originalRenderMode` (for toggle persistence), `documentIDs`, `activeDocumentIndex`, `width`
  - `PanelColumnView` — SwiftUI view rendering a single column; title bar with badge/toggle pills/drag handle/close button; scrollable tab bar for multi-document columns; role-based border; `.onDrag` (UUID payload) and `.onDrop` (`ColumnDropDelegate`)
  - `ColumnDropDelegate` — `DropDelegate`; decodes source UUID asynchronously from `NSItemProvider`; calls `DynamicPanelLayout.moveColumn(id:to:)`; File Tree constraint enforced at the model level
  - `DropZoneView` — 8 pt invisible drop zone between columns; blue tint on hover; calls `layout.addColumn(renderMode:at:)` on drop to create a new column
  - `SputnikAlert` — `Error Sendable Equatable` enum for typed error dialogs
  - `SputnikError` — `Error Sendable` enum for hardware/process errors
  - `HelpTopic` — `Codable Sendable CaseIterable Identifiable` enum for help panel kind
  - `HelpRequest` — `Equatable Sendable` value type; Foundation-owned single route for help-panel navigation (ISS-008 resolved)
  - `AboutWindowView` — SwiftUI About window
  - `DockedScratchpadPanel` / `ScratchpadTextView` — docked scratchpad via `NSViewRepresentable` (SW-3); replaces floating `ScratchpadPanel`
  - `SlashCommandPopup` — filtered command list
  - `StatusBarView` — SwiftUI bottom bar with satellite animation, AI model segments, RAM/CPU

- **Threading model:** All UI work is `@MainActor`. Design tokens are pure value types with no threading concerns. Panel drag operations update `DynamicPanelLayout` synchronously on the main thread via async callback from `NSItemProvider.loadItem` dispatched to `@MainActor`.
- **Data flow:**
  - `DynamicPanelLayout` is read at launch from `PersistenceService` (2.5) via `LayoutState.dynamicLayout`.
  - Panel drag-to-move: `.onDrag` in `PanelColumnView` → `NSItemProvider(uuidString)` → `.onDrop` in target column (`ColumnDropDelegate`) or drop zone (`DropZoneView`) → decode UUID → call `moveColumn` or `addColumn` on `DynamicPanelLayout`.
  - Panel close: ✕ button → `DynamicPanelLayout.removeColumn(id:)` → if last column, restore `.default`.
  - Render-mode toggle: pill buttons → `DynamicPanelLayout.toggleRenderMode(ofColumnID:to:)`; tap on toggled preview column → `revertToggleIfNeeded` → back to `.textEditor`.
  - Auto-position on file open: `ContentView.onChange(of: activeDocumentID)` calls `moveActiveEditorAdjacentToFileTree` for text-type files.
- **State owned:**
  - Design tokens (`SputnikSpacing`, `SputnikFont`, `SputnikColor`) — static, no runtime state.
  - `DynamicPanelLayout` — owned by `LayoutState` (2.5); UI/UX reads and writes through it.
- **Dependencies:** `SettingsStore` (2.3) for theme; `PersistenceService` (2.5) for layout persistence.
- **Failure modes:**
  - Drag payload decode failure → drop silently ignored; no crash.
  - File Tree dropped at invalid position → `moveColumn` guard rejects; column stays put.
  - Last column closed → `removeColumn` restores `.default`; never empty.
  - Light/dark mode change while app is running → `SputnikColor` resolves dynamically via `colorScheme` environment value; no manual refresh needed.
  - Error dialog presented with no active window → `SputnikAlert` is queued and shown once a window becomes key; never silently dropped.

## Invariants
- `SputnikColor` resolves dynamically via SwiftUI `@Environment(\.colorScheme)` — no manual refresh needed on light/dark change
- `DynamicPanelLayout.columns` is never empty — removing the last column restores `.default`
- `.fileTree` column: at most one, always at index 0 or last (enforced at both UI `validateDrop` and model `moveColumn`)
- Terminal is pinned to the bottom strip — not part of the column system, not a valid drop target
- Column role (`active` / `activePair` / `viewOnly`) is computed fresh each render from `activeColumnID` and document ID — never cached
- Scratchpad is always docked bottom-right (beside Terminal) — floating overlay removed
- `HelpRequest` is the **single** Foundation route for help-panel navigation — no module bypasses it (ISS-008 resolved)
- `DocumentTabBar` drag-to-reorder goes through `WindowState.moveDocument(fromOffsets:toOffset:)` — reordered order persists (ISS-019)
- `revertToggleIfNeeded` is called BEFORE setting `activeColumnID` in the focus tap gesture — order matters for correct toggle state

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
