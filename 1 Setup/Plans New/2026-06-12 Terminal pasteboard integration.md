---
plan: Add terminal pasteboard integration — text selection, copy, and paste
status: new
created: 2026-06-12
author: Zed (code analysis)
issue: ISS-059
---

## Summary

The terminal has no text selection, copy, or paste support. `TerminalTextView` draws cells with raw Core Text and is not an `NSTextView` — there is no `mouseDragged` selection tracking, no selected-range model, no ⌘C to copy terminal output, and no ⌘V to paste clipboard content into the shell. ⌘C/⌘V are currently silently swallowed by `keyDown(with:)` because `KeyEncoder.encode` returns `nil` for Command-combos.

Since the renderer jumps straight to Core Text, this requires building a selection model from scratch over the cell grid.

---

## Current State

`TerminalTextView` is a plain `NSView` subclass that:

1. Draws each character cell directly via `NSAttributedString.draw(in:)` — no `NSTextStorage`, no `NSLayoutManager`
2. Has no selection tracking — `mouseDown(with:)` only calls `makeFirstResponder` then `super` (line 125–128)
3. Has no `mouseDragged(with:)` override
4. Has no `selectedRange`, `selectedText`, or similar property
5. Forwards all keystrokes through `KeyEncoder.encode()`, which returns `nil` for Command-combos (so ⌘C/⌘V are no-ops)

The `EmulatorSnapshot` provides the full cell grid `[[ScreenCell]]` and scrollback. Each `ScreenCell` has a `character: Character`. The view already iterates every cell to render it — the same iteration can be used to produce selected text.

---

## Design

### Overview

Three components:

| Component | What it does |
|---|---|
| **Selection model** | Track the anchor (start) and active (current) cell positions during drag. Store the selected row × column range on the view. |
| **Copy (⌘C)** | Iterate the selected cell range, join characters row-by-row, write to `NSPasteboard.general`. |
| **Paste (⌘V)** | Read from `NSPasteboard.general`, encode as UTF-8 `Data`, forward through `onKeyInput`. |

### 1. Selection tracking

Add a selection model to `TerminalTextView`:

```swift
// Selection state
private var selectionStart: (row: Int, col: Int)?
private var selectionEnd: (row: Int, col: Int)?

/// The current selection as a set of cell positions. Computed from start/end.
private var selectedCells: Set<CellPosition>? {
    guard let start = selectionStart, let end = selectionEnd else { return nil }
    // Normalise: rowStart ≤ rowEnd
    let rowStart = min(start.row, end.row)
    let rowEnd   = max(start.row, end.row)
    let colStart = rowStart == start.row ? min(start.col, end.col) : 0  // full rows in between
    let colEnd   = rowEnd   == end.row   ? max(start.col, end.col) : (cols - 1)
    // ... produce Set of (row, col) tuples
}
```

Override `mouseDown` to begin a selection:

```swift
public override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let (row, col) = cellPosition(for: event)
    selectionStart = (row, col)
    selectionEnd = (row, col)
    needsDisplay = true
}
```

Override `mouseDragged` to extend the selection:

```swift
public override func mouseDragged(with event: NSEvent) {
    let (row, col) = cellPosition(for: event)
    selectionEnd = (row, col)
    needsDisplay = true
}
```

Add a helper to convert `NSEvent` location to cell coordinates:

```swift
private func cellPosition(for event: NSEvent) -> (row: Int, col: Int) {
    let point = convert(event.locationInWindow, from: nil)
    let col = Int(point.x / cellWidth)
    let row = Int((bounds.height - point.y) / cellHeight)
    // Clamp to grid bounds
    let totalLines = (snapshot?.scrollback.count ?? 0) + (snapshot?.grid.count ?? 0)
    return (
        row: max(0, min(row, totalLines - 1)),
        col: max(0, min(col, Int(lastReportedCols) - 1))
    )
}
```

### 2. Visual selection (drawing)

In `draw(_:)`, after drawing the background fill for each cell, check if the cell is selected and draw a highlighted background:

```swift
// Inside the cell-drawing loop, after bg fill:
let isSelected = selectedCells?.contains(CellPosition(row: lineIdx, col: colIdx)) ?? false
if isSelected {
    NSColor.selectedTextBackgroundColor.withAlphaComponent(0.5).setFill()
    ctx.fill(cellRect)
}
```

The `selectedTextBackgroundColor` is the standard macOS selection highlight — it automatically follows the user's accent colour preference.

### 3. Copy (⌘C)

Intercept ⌘C in `keyDown(with:)` before the KeyEncoder path. If there is a selection, copy it and return. Otherwise fall through (no-op, since ⌘C without selection shouldn't reach the shell).

```swift
public override func keyDown(with event: NSEvent) {
    // Intercept Command+C before KeyEncoder.
    if event.modifierFlags.contains(.command),
       event.charactersIgnoringModifiers == "c"
    {
        copySelectionToPasteboard()
        return
    }
    
    // Intercept Command+V for paste.
    if event.modifierFlags.contains(.command),
       event.charactersIgnoringModifiers == "v"
    {
        pasteFromPasteboard()
        return
    }
    
    // Existing key handling...
    // ... (line 132-148 unchanged)
}
```

`copySelectionToPasteboard()` iterates the selected cells row-by-row and builds a string:

```swift
private func copySelectionToPasteboard() {
    guard let selected = selectionCells,
          let snapshot = snapshot,
          !selected.isEmpty
    else { return }
    
    let grid = snapshot.scrollback + snapshot.grid
    let sorted = selected.sorted { $0.row != $1.row ? $0.row < $1.row : $0.col < $1.col }
    
    var lines: [String] = []
    var currentRow = -1
    var currentLine = ""
    
    for pos in sorted {
        if pos.row != currentRow {
            if !currentLine.isEmpty {
                lines.append(currentLine)
            }
            currentRow = pos.row
            currentLine = ""
        }
        let cell = grid[pos.row][pos.col]
        currentLine.append(cell.character)
    }
    if !currentLine.isEmpty {
        lines.append(currentLine)
    }
    
    let text = lines.joined(separator: "\n")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
```

### 4. Paste (⌘V)

Intercept ⌘V and write clipboard text to the PTY:

```swift
private func pasteFromPasteboard() {
    guard let text = NSPasteboard.general.string(forType: .string),
          let data = text.data(using: .utf8)
    else { return }
    onKeyInput?(data)
}
```

No need to strip trailing newlines — the shell handles them naturally.

### 5. Clear selection on Escape or new output

When the user presses Escape, or the emulator snapshot updates with new output, clear the selection so stale highlights don't linger:

```swift
// In update(snapshot:profile:):
public func update(snapshot: EmulatorSnapshot, profile: TerminalProfile) {
    // Clear selection on new output — the grid has scrolled.
    if self.snapshot != nil {
        selectionStart = nil
        selectionEnd = nil
    }
    // ... existing code ...
}

// In keyDown, add Escape to clear selection:
if event.keyCode == 53 { // Escape
    selectionStart = nil
    selectionEnd = nil
    needsDisplay = true
    // Don't return — still forward Escape to the shell
}
```

---

## Steps

### Step 1 — Add selection model to `TerminalTextView`

1. Add `selectionStart: (row: Int, col: Int)?` and `selectionEnd: (row: Int, col: Int)?` stored properties
2. Add a `CellPosition` struct or use a tuple typealias for clarity
3. Implement `cellPosition(for:)` helper
4. Override `mouseDown(with:)` to set both start and end
5. Override `mouseDragged(with:)` to update end
6. Build and test: drag across terminal text — no visible effect yet, but the state is tracked

### Step 2 — Draw selection highlight

1. In the cell-drawing loop in `draw(_:)`, compute `isSelected` from the selection model
2. Draw `NSColor.selectedTextBackgroundColor.withAlphaComponent(0.5)` over selected cells
3. Build and test: drag across text — cells highlight with the system accent colour

### Step 3 — Wire ⌘C to copy

1. Intercept ⌘C in `keyDown(with:)` before the KeyEncoder path
2. Implement `copySelectionToPasteboard()`
3. Add Escape to clear selection (but still forward the Escape key to the shell)
4. Build and test: select text with mouse, press ⌘C, paste into TextEdit

### Step 4 — Wire ⌘V to paste

1. Intercept ⌘V in `keyDown(with:)`
2. Implement `pasteFromPasteboard()`
3. Build and test: copy text from TextEdit, press ⌘V in the terminal

### Step 5 — Clear selection on new output

1. In `update(snapshot:profile:)`, if the snapshot changes (new shell output arrived), clear the selection
2. Build and test: run a command while text is selected — selection clears

### Step 6 — Add a `CellPosition` type

Create a small `Sendable` struct or use tuples. For clarity across the selection code, a dedicated type is worthwhile:

```swift
/// A position in the terminal grid. Row 0 is the oldest scrollback line.
struct CellPosition: Hashable, Sendable {
    let row: Int
    let col: Int
}
```

Place it in a new file `7 Terminal/CellPosition.swift` (SR-6 — one type per file).

### Step 7 — Update the Module Guide

In `1 Setup/Module Guides/7 Terminal/guide.md`:

- **Key types:** Add `CellPosition` to the list
- **Data flow → User interaction:** Add a section on text selection (mouse down → drag → ⌘C) and paste (⌘V)
- **Threading model:** Note that selection state is `@MainActor` (on the `TerminalTextView` which is already main-actor-bound)

## Risk Assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| Selection performance with large scrollback | Low | Selection highlight is a simple containment check per cell in the draw loop. The draw loop already iterates every cell. The `Set<CellPosition>` lookup is O(1). |
| Accidental copy when user meant ⌘C for SIGINT | Low | The existing `KeyEncoder` already returns `nil` for Command-combos (line 61), so ⌘C never reached Zsh. This is an improvement — now it does something useful. |
| Paste injects control characters from rich clipboard formats | Low | `.string(forType: .string)` returns plain text only. RTF, HTML, and other rich formats are ignored. |
| Selection is lost on output flood | Low | This is intentional — stale selection highlights over new output would be confusing. |

## Success Criteria

- User can select terminal output by clicking and dragging with the mouse
- Selected cells are highlighted with the system accent colour
- ⌘C copies selected text to the system pasteboard
- ⌘V pastes clipboard text into the shell
- Selection clears when new output arrives or when Escape is pressed
- A file-scope `CellPosition` struct exists in its own file

## Post-Plan

- [ ] Move this plan to `Plans Completed/` when all steps are done.
- [ ] Update ISS-059 status to `Resolved` in `References/Issues.md`.
