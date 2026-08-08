---
module: 2.4 UI and UX
status: stable
last_updated: 2026-06-12
last_verified: 2026-06-12
open_issues: ISS-066, ISS-067
---

## Purpose
Provides the visual layout primitives, design tokens, and UI components shared by every panel: the dynamic column layout model, column views, drop zones, resize dividers, focus coordination, badges, help overlays, status bar, and about window.

## Diagram

```
┌─ SputnikApp ──────────────────────────────────────────────────────────┐
│  ContentView                                                           │
│  ┌─ GeometryReader ──────────────────────────────────────────────────┐ │
│  │  HStack                                                           │ │
│  │  ┌──────────┐ ┌─ 8pt ─┐ ┌──────────┐ ┌─ 8pt ─┐ ┌──────────┐     │ │
│  │  │PanelCol  │ │Resize │ │PanelCol  │ │Resize │ │PanelCol  │     │ │
│  │  │  View    │ │Divider│ │  View    │ │Divider│ │  View    │     │ │
│  │  │(editor)  │ │+Drop  │ │(preview) │ │+Drop  │ │(viewer)  │     │ │
│  │  │<─ badge  │ │ Zone  │ │<─ badge  │ │ Zone  │ │<─ badge  │     │ │
│  │  └──────────┘ └───────┘ └──────────┘ └───────┘ └──────────┘     │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│  ┌─ Terminal strip ───────┬── Docked Scratchpad ────────────────────┐ │
│  │ badge + "Terminal"     │  badge + "Scratchpad"   │               │ │
│  └────────────────────────┴─────────────────────────┘               │ │
│  ┌─ StatusBarView ──────────────────────────────────────────────────┐ │
│  └──────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘
```

## Source Files

| File | Responsibility |
|---|---|
| `DynamicPanelLayout.swift` | Ordered column list model; add/move/remove/resize mutations; width-proportion invariants; `ColumnRole` computation |
| `PanelColumn.swift` | Single column data: `id`, `renderMode`, `width`, document tab IDs, `originalRenderMode` for toggle |
| `PanelID.swift` | Enum of every panel kind; `displayBadge` (short code) and `displayName` (human-readable) — single source of truth for panel identity |
| `PanelFocusCoordinator.swift` | Keyboard focus cycling between columns and Terminal; `PanelFocusTarget` enum |
| `SputnikColor.swift` | Semantic colour tokens (accent, separator, background, text levels) |
| `DesignTokens.swift` | `SputnikSpacing` and `SputnikFont` constants |
| `DocumentTabBar.swift` | Multi-tab strip inside a column; drag-to-reorder tabs |
| `StatusBarView.swift` | Bottom bar: RAM/CPU, AI model info, processing indicator |
| `AboutWindowView.swift` | F-2 About window |
| `SputnikAlert.swift` | Modal alert wrapper for terminal/auth/recovery dialogs |
| `HelpTopic.swift` + `HelpRequest.swift` | Help panel routing types |
| `App-Sputnik/PanelColumnView.swift` | Column chrome: badge pill, title bar, toggle pills, drag handle, close button, tab bar, role border, focus indicator |
| `App-Sputnik/ContentView.swift` | Root layout: HStack of columns with GeometryReader width application, terminal strip, scratchpad, help overlay, toolbar |
| `App-Sputnik/ResizeDivider.swift` | Drag-to-resize divider between columns with haptic detent |
| `App-Sputnik/ColumnDropDelegate.swift` | Drop delegate for column-onto-column tab creation |
| `App-Sputnik/DropZoneView.swift` | Between-column drop zone with hover highlight |
| `App-Sputnik/DockedScratchpadPanel.swift` | Docked scratchpad with badge pill |

## Technical Summary

- **Frameworks:** SwiftUI for declarative layout; AppKit cursors and haptic feedback for resize/reorder interactions
- **Threading:** All layout mutations on `@MainActor`; `DynamicPanelLayout` is `Sendable` by value copy
- **Data flow:** `ContentView` reads `WindowState.layout.dynamicLayout` → computes column widths via `GeometryReader` → binds into `DynamicPanelLayout` via manual `Binding` wrappers → mutations (resize, reorder, add/remove) flow through `DynamicPanelLayout` methods
- **Dependencies:** `FoundationModule` (PanelID, PanelColumn, DynamicPanelLayout, design tokens, SputnikColor), `SwiftUI`, `UniformTypeIdentifiers`
- **Failure modes:** Drag-resize clamps to `minColumnWidthProportion` (0.08) to prevent zero-width columns; width proportions always sum to ~1.0 after mutations; geometry fallback to 1 px when window is too narrow

## Invariants

- `DynamicPanelLayout.columns` is never empty (removing last column restores `.default`)
- At most one `.fileTree` column, always at index 0 or last
- After every mutation, column width proportions sum to approximately 1.0 (within floating-point tolerance)
- No column ever renders narrower than `minColumnWidthProportion * availableWidth`
- `moveColumn` preserves widths (no rescaling — column count unchanged)
- `addColumn` rescales existing columns proportionally; `removeEmptyColumns` redistributes freed width pro-rata
- `resetToEvenWidths()` is never called automatically — only via explicit user action (Restore Default Layout)
- The `ResizeDivider` only shifts width between its two immediate neighbours (left index and left+1) — it never touches other columns
- All badges derive from `PanelID.displayBadge`; all accessibility names from `PanelID.displayName` — a single source of truth
- Role borders (solid vs dashed) and focus indicators (full ring vs top-edge line) are distinguishable by shape/position, not colour alone
