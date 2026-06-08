---
module: 3.5 Spelling and Grammar Check
status: draft
last_updated: 2026-06-07
---

## Purpose
Performs real-time spelling and grammar checking with instant quickfix suggestions inside the text editor — gated to natural-language file types only (.txt, .md) — using macOS's native `NSSpellChecker` to keep correction latency near zero without any third-party dependency.

## Diagram
```
  File opened in NSTextView (3.1)
           │
           ▼
  SpellCheckFileTypeGuard
  ┌──────────────────────────────┐
  │  allowed: .txt  .md          │
  │  blocked: .html  binary      │
  │  (checked once on file open) │
  └──────────────────────────────┘
      │ allowed        │ blocked
      ▼                ▼
  Checker ON       Checker OFF
                   (no underlines,
                    no menu items)
      │
      ▼
  Text change in NSTextStorage
      │
      ▼
  DebounceTimer (Foundation 2.7)
      │  typing paused
      ▼
  SpellingGrammarChecker
  (NSSpellChecker wrapper)
      │
      ▼
  NSTextCheckingResult[ ]
  ┌─────────────────────────────────────┐
  │  .spelling  →  red underline   ~~~  │
  │  .grammar   →  green underline ===  │
  └─────────────────────────────────────┘
      │
      ▼
  Underline attributes applied
  to NSTextStorage ranges
      │
      │  user right-clicks underline
      ▼
  QuickfixPresenter
  (NSMenu with correction list)
      │  user selects correction
      ▼
  NSTextStorage replaceCharacters(in:with:)
```

## Technical Summary
- **Framework(s):** AppKit (`NSSpellChecker`, `NSTextCheckingResult`, `NSTextView`, `NSTextStorage`), Foundation
- **Key types:**
  - `SpellCheckFileTypeGuard` — checks the open file's extension on file open; enables the checker for `.txt` and `.md`; disables it for all other types (`.html`, binary, etc.); result sets `EditorViewModel.spellCheckActive` <!-- assumed -->
  - `SpellingGrammarChecker` — subscribes to `NSTextStorage` change notifications; calls `NSSpellChecker.check(_:range:types:options:inSpellDocumentWithTag:orthography:wordCount:)` after debounce; writes `.spelling` results as red underline attributes and `.grammar` results as green underline attributes to `NSTextStorage`; only runs when `spellCheckActive` is `true` <!-- assumed -->
  - `QuickfixPresenter` — intercepts right-click on an underlined range; presents an `NSMenu` populated with `NSSpellChecker` correction candidates; applies the chosen correction via `NSTextStorage` replacement <!-- assumed -->
- **Threading model:** `SpellCheckFileTypeGuard` runs on `Task(priority: .userInitiated)` at file open; `NSSpellChecker` calls and all `NSTextStorage` attribute mutations on `@MainActor` (AppKit requirement); debounce via `DebounceTimer` (Foundation 2.7)
- **Data flow:** file open → `SpellCheckFileTypeGuard` sets `spellCheckActive` → text change → `DebounceTimer` → `SpellingGrammarChecker.check(range:)` → `NSTextCheckingResult` array → red/green underline attributes written to `NSTextStorage` → user right-clicks underline → `QuickfixPresenter` fetches candidates → correction applied
- **State owned:** `spellCheckActive` flag (owned by `EditorViewModel` in 3.1); current `NSTextCheckingResult` annotation list; spell-checker document tag (identifies the document session to `NSSpellChecker`)
- **Dependencies:** 3.1 Text — `NSTextStorage`, `NSTextView` delegate, `EditorViewModel`; Foundation 2.7 Utilities — `DebounceTimer`; Module 2 Foundation — settings (language/locale, spelling enabled toggle, grammar check enabled toggle)
- **Failure modes:** file type not in allowlist → checker stays off, no underlines, no error shown; `NSSpellChecker` shared instance unavailable → disable gracefully, no underlines, no error surfaced; correction range no longer valid after a concurrent edit → no-op, menu dismisses cleanly; locale not supported by `NSSpellChecker` → fall back to system default locale

## Spec Reference
> Extracted verbatim from `readme.md`:

```
  9. Spelling and Grammar checking (Instant Quickfix)
```
