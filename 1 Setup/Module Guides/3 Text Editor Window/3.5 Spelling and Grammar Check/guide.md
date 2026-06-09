---
module: 3.5 Spelling and Grammar Check
status: active
last_updated: 2026-06-08
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
  ┌─────────────────────────────────────────────┐
  │  .spelling  →  red underline    ~~~         │
  │  .grammar   →  orange underline ===         │
  │  spelling-over-grammar: a grammar issue     │
  │  overlapping a spelling issue is kept in    │
  │  the model but suppressed (not drawn)       │
  └─────────────────────────────────────────────┘
      │
      ▼
  GrammarAnnotation[ ]  (hit-testable model)
  + underline attributes on NSTextStorage ranges
      │
      │  user single-clicks an underline
      ▼
  QuickfixPopover (SwiftUI in NSPopover)
  ┌─────────────────────────────────────────────┐
  │  Fix → NSTextStorage replaceCharacters       │
  │        then re-check (underline refreshes)   │
  │  Dismiss → ignore word/phrase, then re-check │
  │        (a suppressed grammar issue surfaces) │
  └─────────────────────────────────────────────┘
```

## Technical Summary
- **Framework(s):** AppKit (`NSSpellChecker`, `NSTextCheckingResult`, `NSTextView`, `NSTextStorage`), Foundation
- **Key types:**
  - `SpellCheckFileTypeGuard` — checks the open file's extension on file open; enables the checker for `.txt` and `.md`; disables it for all other types (`.html`, binary, etc.); result sets `EditorViewModel.spellCheckActive` <!-- assumed -->
  - `SpellingGrammarChecker` — subscribes to `NSTextStorage` change notifications; calls `NSSpellChecker.check(_:range:types:options:inSpellDocumentWithTag:orthography:wordCount:)` after debounce; writes `.spelling` results as **red** underlines and `.grammar` results as **orange** underlines to `NSTextStorage`; rebuilds a parallel `[GrammarAnnotation]` model on each pass; applies **spelling-over-grammar** priority (a grammar annotation overlapping a spelling range is kept but `isSuppressed`, so it is not drawn); maintains a per-document dismissed set (spelling via `NSSpellChecker.ignoreWord`, grammar via a local phrase set); only runs when `spellCheckActive` is `true`
  - `GrammarAnnotation` — `Sendable` value type (`range`, `kind`, `suggestions`, `isSuppressed`) giving the editor a hit-testable model so a click maps back to an issue and its fixes (SR-6)
  - `QuickfixPopover` — SwiftUI Fix/Dismiss popover (SW-3) hosted in an `NSPopover` by `EditorTextView`; **Fix** applies a suggestion via `NSTextStorage.replaceCharacters` then re-checks; **Dismiss** ignores the word/phrase then re-checks (surfacing any grammar issue the dismissed spelling word was suppressing)
  - `EditorTextView` (3.1) — single left-click hit-tests the annotation model and presents `QuickfixPopover`; `menu(for:)` appends a "Look Up in … Help" item for the active mode, resolves the selection through the matching module-9 coordinator, and routes the result via `AppState.requestedHelpTarget` (Foundation `HelpRequest`)
  - `QuickfixPresenter` — earlier right-click correction `NSMenu`; superseded for the primary flow by the single-click `QuickfixPopover`, retained as a component <!-- assumed -->
- **Threading model:** `SpellCheckFileTypeGuard` runs on `Task(priority: .userInitiated)` at file open; `NSSpellChecker` calls and all `NSTextStorage` attribute mutations on `@MainActor` (AppKit requirement); debounce via `DebounceTimer` (Foundation 2.7)
- **Data flow:** file open → `SpellCheckFileTypeGuard` sets `spellCheckActive` → text change → `DebounceTimer` → `SpellingGrammarChecker.runCheck()` → `NSTextCheckingResult` array → `[GrammarAnnotation]` model + red/orange underline attributes (grammar suppressed where it overlaps spelling) → user single-clicks underline → `QuickfixPopover` → Fix (replace + re-check) or Dismiss (ignore + re-check)
- **State owned:** `spellCheckActive` flag (owned by `EditorViewModel` in 3.1); current `[GrammarAnnotation]` model; per-document dismissed grammar phrases; spell-checker document tag (identifies the document session to `NSSpellChecker`). Right-click help routing is owned by Foundation via `AppState.requestedHelpTarget` (`HelpRequest`), consumed by module 9 panels.
- **Dependencies:** 3.1 Text — `NSTextStorage`, `NSTextView` delegate, `EditorViewModel`; Foundation 2.7 Utilities — `DebounceTimer`; Module 2 Foundation — settings (language/locale, spelling enabled toggle, grammar check enabled toggle)
- **Failure modes:** file type not in allowlist → checker stays off, no underlines, no error shown; `NSSpellChecker` shared instance unavailable → disable gracefully, no underlines, no error surfaced; correction range no longer valid after a concurrent edit → no-op, menu dismisses cleanly; locale not supported by `NSSpellChecker` → fall back to system default locale

## Spec Reference
> Extracted verbatim from `readme.md`:

```
  9. Spelling and Grammar checking (Instant Quickfix)
```
