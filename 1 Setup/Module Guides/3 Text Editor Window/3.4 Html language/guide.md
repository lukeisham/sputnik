---
module: 3.4 Html language
status: draft
last_updated: 2026-06-07
---

## Purpose
Adds HTML-specific editing intelligence to the base text editor — debounced inline ghost-text tag and attribute suggestions, activated only when the file contains `<!DOCTYPE html>` — and exposes a "Render as HTML" command that opens the HTML Preview panel (module 8) with the current file.

## Diagram
```
  File opened in NSTextView (3.1)
           │
           ▼
  HTMLDocTypeGuard
  ┌─────────────────────────────────┐
  │  scan first ~512 bytes for      │
  │  <!DOCTYPE html>                │
  │  (case-insensitive)             │
  └─────────────────────────────────┘
      │ found          │ not found
      ▼                ▼
  HTML mode ON     HTML mode OFF
  (suggestions     (no suggestions,
   + menu item)     menu item hidden)
      │
      ├─── Keypress path ──────────────────────────┐
      │                                            │
      ▼                                            │
  DebounceTimer (async Task sleep)                 │
      │  typing paused                             │
      ▼                                            │
  HTMLLanguageProvider                             │
  ┌──────────────────────────┐                     │
  │  detect partial tag,     │                     │
  │  attribute, or closing   │                     │
  │  tag at cursor position  │                     │
  └──────────────────────────┘                     │
      │  suggestion string                         │
      ▼                                            │
  GhostTextOverlay                                 │
  (greyed secondary attribute                      │
   after cursor in NSTextView)                     │
      │  Tab / Esc                                 │
      ▼                                            │
  Accept → insert   Dismiss → clear                │
                                                   │
      ├─── "Render as HTML" menu path ─────────────┘
      │    File menu → "Render as HTML"  (⌘⌥P)
      ▼
  Foundation inter-panel router (2.1)
      │  open HTML Preview panel (module 8)
      ▼
  HTML Preview panel renders current file
```

## Technical Summary
- **Framework(s):** AppKit (`NSTextView`, `NSTextStorage`), Foundation
- **Key types:**
  - `HTMLDocTypeGuard` — scans the first ~512 bytes of `NSTextStorage` content (case-insensitive) for `<!DOCTYPE html>`; returns a `Bool`; re-runs on file open and on each full document reload; result sets `EditorViewModel.htmlModeActive` <!-- assumed -->
  - `HTMLLanguageProvider` — parses partial HTML tags and attributes at the cursor; returns a completion string (e.g. closes an open tag, suggests common attributes); only invoked when `htmlModeActive` is `true` <!-- assumed -->
  - `GhostTextOverlay` — shared with 3.2/3.3; lives in 3.1 Text <!-- assumed -->
  - `RenderAsHTMLCommand` — an `NSMenuItem` action wired into the File menu under "Render as HTML" (shortcut ⌘⌥P); calls the Foundation inter-panel router to show module 8 with the current file URL; only enabled when `htmlModeActive` is `true` <!-- assumed -->
- **Threading model:** `HTMLDocTypeGuard` scan on `Task(priority: .userInitiated)` (runs at file open); completion generation on `Task(priority: .utility)`; all `NSTextStorage` and UI updates on `@MainActor`
- **Data flow:**
  - *Activation:* file open → `HTMLDocTypeGuard.check(_:)` → sets `htmlModeActive` → enables suggestions and "Render as HTML" menu item
  - *Suggestions:* keypress → debounce → `HTMLLanguageProvider.suggest(at: cursorRange)` → `GhostTextOverlay.show(_:)` → user accepts (Tab) or dismisses
  - *Render:* user triggers "Render as HTML" → `RenderAsHTMLCommand` → Foundation 2.1 inter-panel router → module 8 HTML Preview panel opens with current file URL
- **State owned:** `htmlModeActive` flag (owned by `EditorViewModel` in 3.1); current ghost-text suggestion string
- **Dependencies:** 3.1 Text — `NSTextView` delegate chain, `NSTextStorage` access, `GhostTextOverlay`, `EditorViewModel`; Foundation 2.7 Utilities — `DebounceTimer`; Foundation 2.1 Inter-panel communication — panel routing for "Render as HTML"; Module 2 Foundation — settings (suggestions enabled toggle, debounce interval); Module 8 HTML Preview — target panel for render command
- **Failure modes:** `<!DOCTYPE html>` absent → HTML mode stays off, no suggestions shown, "Render as HTML" item hidden; doctype present but malformed HTML → suggestions degrade gracefully (provider returns nil, ghost text clears); "Render as HTML" triggered while module 8 panel is already open → bring existing panel to front, reload content; `HTMLDocTypeGuard` scan on a very large file → limited to first 512 bytes so scan time is bounded regardless of file size

## Spec Reference
> Extracted verbatim from `readme.md`:

```
  11. HTML language support (Inline Suggestions / Ghost Text, Debouncing)
```
