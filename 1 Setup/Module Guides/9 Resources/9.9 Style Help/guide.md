---
module: 9.9 Style Help
status: active
last_updated: 2026-09-28
last_verified: 2026-06-29
open_issues: none
---

## Purpose
Provide a library of English writing-style reference topics derived from the open-source style guide *The Elements of Style* by William Strunk Jr. (1919, public domain), plus supplementary modern topics, browsable in a dedicated panel and accessible via right-click context lookup from Text Editor, Markdown Preview, and HTML Preview.

## Source Files
| File | Responsibility |
|---|---|
| `StyleHelpContent.swift` | Topic model conforming to `HelpTopicProtocol` (no structuralLevel — always guidance-level) |
| `StyleHelpIndex.swift` | Actor that loads and searches `style_help_index.json` |
| `StyleHelpCoordinator.swift` | `@MainActor` coordinator for context-sensitive lookup (lexical-only) |
| `StyleHelpPanelView.swift` | SwiftUI view wrapping `SputnikHelpPanel<StyleHelpContent>` |

## Technical Summary
- **Content source**: `Style/style_open_source.md` → extracted into `9 Resources/9.9 Style Help/*.md` → indexed in `style_help_index.json`
- **Valid categories**: `usage`, `composition`, `form`, `word-usage`, `structure`, `voice`
- **Content structure**:
  - Chapter II (Rules 1–7): Elementary Rules of Usage (`usage`)
  - Chapter III (Rules 8–18): Elementary Principles of Composition (`composition`)
  - Chapter IV: A Few Matters of Form (`form`)
  - Chapter V: Words and Expressions Commonly Misused (~35 entries, `word-usage`)
  - Supplementary topics: structure, voice, modern usage, punctuation gaps, additional word pairs
- **Framework**: SwiftUI + actor-based index loading; coordinator on `@MainActor`
- **Threading**: Index loads off-main-actor; all access is `await`-ed
- **Dependencies**: `FoundationModule` for `HelpTopicProtocol`, `SputnikHelpPanel`, `SputnikColor`, `SputnikFont`, `SputnikSpacing`
- **Context lookup**: `StyleHelpCoordinator.lookup(word:source:)` — lexical-only lookup (no structural analyzer)
- **Panel**: Registered via `SputnikHelpPanel` wrapper; `onNavigate` wired to `AppState.requestedHelpTarget`
- **No structural analyzer** — style lookup is always lexical
- **Only natural-language help:** Grammar Help (9.5) was removed on 2026-09-28. Plain text in the editor, the Markdown Preview and the HTML Preview use `.style` for More Context and Interaction

## Invariants
- All index access goes through `await StyleHelpIndex.shared`
- Style topics live exclusively in `9 Resources/9.9 Style Help/`
- `style_help_index.json` bundles ALL style topics
- `StyleHelpContent` has no `structuralLevel` field — all style guidance is lexical
- Content derived from Strunk (1919) is in the public domain; supplementary topics are original
