---
module: 3.2 Markdown Language
status: draft
last_updated: 2026-06-07
---

## Purpose
Adds Markdown-specific editing intelligence to the base text editor — debounced inline ghost-text suggestions and syntax-aware completions — so users get context-sensitive Markdown assist as they type.

## Diagram
```
  Keypress in NSTextView (3.1)
           │
           ▼
    DebounceTimer (async Task sleep)
           │  typing paused
           ▼
  MarkdownLanguageProvider
  ┌─────────────────────────┐
  │  pattern match cursor   │
  │  context (heading, list,│
  │  link, code fence …)    │
  └─────────────────────────┘
           │  suggestion string
           ▼
    GhostTextOverlay
    (secondary NSTextAttribute
     appended after cursor)
           │  Tab / Esc
           ▼
    Accept → insert   Dismiss → clear
```

## Technical Summary
- **Framework(s):** AppKit (`NSTextView`, `NSTextStorage`), Foundation
- **Key types:**
  - `MarkdownLanguageProvider` — inspects cursor context and returns a suggestion string for common Markdown patterns (headings, lists, links, fenced code blocks) <!-- assumed -->
  - `GhostTextOverlay` — renders the suggestion as a greyed secondary attribute in `NSTextStorage`; removed on any non-Tab keypress; lives in 3.1 Text <!-- assumed -->
- **Threading model:** Suggestion generation runs on `Task(priority: .utility)`; ghost-text attribute writes happen on `@MainActor` via the `NSTextView` delegate
- **Data flow:** keypress → cancel previous debounce → start new `DebounceTimer` → `MarkdownLanguageProvider.suggest(at: cursorRange)` → ghost-text string → `GhostTextOverlay.show(_:)` → user accepts (Tab) or dismisses (any other key)
- **State owned:** current ghost-text suggestion string
- **Dependencies:** 3.1 Text — `NSTextView` delegate chain, `NSTextStorage` access, `GhostTextOverlay`; Foundation 2.7 Utilities — `DebounceTimer`; Module 2 Foundation — settings (suggestions enabled toggle, debounce interval)
- **Failure modes:** suggestion generation throws or returns nil → clear ghost text silently, no visible error; debounce `Task` cancelled by new keypress → expected behaviour, restart timer; `NSTextStorage` edit conflict → discard suggestion and clear overlay

## Spec Reference
> Extracted verbatim from `readme.md`:

```
  12. Markdown language support (Inline Suggestions / Ghost Text, Debouncing)
```
