---
module: 9.5 Grammar Help
status: active
last_updated: 2026-06-29
last_verified: 2026-06-29
open_issues: none
---

## Purpose
Provide a library of English grammar reference topics browsable in a dedicated help panel and accessible via right-click context lookup from Text Editor, Markdown Preview, and HTML Preview.

## Source Files
| File | Responsibility |
|---|---|
| `GrammarHelpContent.swift` | Topic model conforming to `HelpTopicProtocol` with `structuralLevel` field |
| `GrammarHelpIndex.swift` | Actor that loads and searches `grammar_help_index.json` |
| `GrammarHelpCoordinator.swift` | `@MainActor` coordinator for context-sensitive lookup with structural-aware scoring |
| `GrammarHelpPanelView.swift` | SwiftUI view wrapping `SputnikHelpPanel<GrammarHelpContent>` |

## Technical Summary
- **Content source**: `9 Resources/9.5 Grammar Help/grammar_help_index.json` → loaded by `GrammarHelpIndex` actor on first access via `Bundle.module`
- **Valid categories**: `punctuation`, `grammar`, `spelling`, `usage`, `edge-cases`, `mechanics`, `sentence-structure`
- **Framework**: SwiftUI + actor-based index loading; coordinator on `@MainActor`
- **Threading**: Index loads off-main-actor; all access is `await`-ed
- **Dependencies**: `FoundationModule` for `HelpTopicProtocol`, `SputnikHelpPanel`, `SputnikColor`, `SputnikFont`, `SputnikSpacing`
- **Context lookup**: `GrammarHelpCoordinator.lookup(word:source:analysisResult:)` — supports structural-vs-lexical prioritization for multi-word selections via `GrammarSelectionAnalyzer`
- **Panel**: Registered via `SputnikHelpPanel` wrapper; `onNavigate` wired to `AppState.requestedHelpTarget`

## Invariants
- All index access goes through `await GrammarHelpIndex.shared`
- Style topics are NEVER hosted here — they belong to 9.9 Style Help
- `grammar_help_index.json` contains only grammar topics (no `"category": "style"` entries)
- `relatedTopics` arrays only reference other grammar topic IDs
- `GrammarHelpContent` uses `GrammarStructuralLevel` for structural-vs-lexical classification
