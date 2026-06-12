# Editing Tools

The ASCII Studio provides a set of editing tools for touching up and refining your ASCII art after conversion. These tools work on the character grid directly, letting you adjust the output without leaving the Studio.

## Toolbar Overview

| Tool | Shortcut | Function |
|---|---|---|
| Paint | `P` | Draw individual ASCII characters onto the grid |
| Eraser | `E` | Replace characters with spaces |
| Fill | `G` | Flood-fill a contiguous area with a character |
| Select | `S` | Select a rectangular region for copy/cut/delete |
| Eyedropper | `I` | Pick a character from the grid |
| Move | `V` | Drag a selection to reposition it |
| Zoom | `Z` | Zoom in to edit individual characters |

## Paint Tool

The Paint tool lets you click or drag to place characters on the grid. Select a character from the character palette (or type it), choose a density level, and paint onto the preview.

**Density levels** map to your chosen ramp: lighter clicks use sparser characters, harder clicks use denser ones.

## Eraser Tool

Replaces characters with spaces. Click or drag to clear areas. The Eraser tool respects the current brush size.

## Fill Tool

Flood-fill: click any contiguous area of the same character, and it will be replaced with your chosen character. Useful for quickly filling backgrounds or correcting converted areas.

## Select Tool

Drag to create a rectangular selection. Once selected:

- **Copy** (⌘C) or **Cut** (⌘X) to clipboard
- **Delete** to clear
- **Move** (V) to drag the selection elsewhere on the grid

## Undo / Redo

The Studio supports unlimited undo (⌘Z) and redo (⇧⌘Z) for all editing operations so you can experiment freely.
