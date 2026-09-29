---
module: 9 Resources
status: active
last_updated: 2026-09-28
last_verified: 2026-06-29
open_issues: none
---

## Purpose
Host all bundled help content, resources, and the orchestration layer for context-sensitive help lookups — bridging the Foundation-owned `HelpTopic`/`HelpContextResolving` abstractions with concrete topic indices and coordinators.

## Diagram
```
Foundation (2.0 App Overview)
  HelpTopic enum (.sputnik, .markdown, .html, .json, .asciiArt, .style)
  HelpContextResolving protocol
        │
        ▼
9 Resources (SputnikHelpContextResolver)
  switch query.kind:
    .style    → StyleHelpCoordinator    → StyleHelpIndex    → style_help_index.json
    .markdown → MarkdownHelpCoordinator → MarkdownHelpIndex
    .html     → HTMLHelpCoordinator     → HTMLHelpIndex
    .json     → JSONHelpCoordinator     → JSONHelpIndex
    .asciiArt → ASCIIArtHelpCoordinator → ASCIIArtHelpIndex
        │
        ▼
  HelpRequest(kind:, topicID:) → AppState.requestedHelpTarget
        │
        ▼
  SputnikHelpPanel<Topic> (per-kind panel view)
```

## Source Files
| File | Responsibility |
|---|---|
| `SputnikHelpContextResolver.swift` | Orchestration: dispatches `HelpContextQuery` to the correct coordinator |
| `SputnikHelpPanel.swift` | Shared SwiftUI panel component parameterized over `Topic: HelpTopicProtocol` |
| `HelpExternalSearch.swift` | External search link model |
| `HelpExternalSearchBuilder.swift` | Builds external search URLs per help kind |
| `Bundle+ResourcesModule.swift` | Bundle accessor for resources |
| `SputnikCompletionCorpus.swift` | Corpus for auto-complete suggestions |
| `9.1 ASCII Library/` | ASCII art character library |
| `9.2 ASCII art Help/` | ASCII Art help topics + index |
| `9.3 Markdown Help/` | Markdown help topics + index |
| `9.4 Html Help/` | HTML help topics + index |
| `9.7 JSON Help/` | JSON help topics + index |
| `9.8 Interaction/` | Resource section index for interaction feature |
| `9.9 Style Help/` | Style help topics + index. The natural-language help for plain text |

## Technical Summary
- **Package**: `ResourcesModule` in `9 Resources/Package.swift`, depends on `FoundationModule`
- **Resources**: All `9.X */` directories are `.process()` bundled via Package.swift
- **Style Help (9.9)** was separated from Grammar Help (9.5) on 2026-06-29. Grammar Help (9.5) was removed on 2026-09-28; Apple's `NSTextView` checker now handles spelling and grammar in the editor, and Style Help is the only natural-language help. There is no `9.5` folder and no `9.5` line in `Package.swift`
- **`SputnikHelpContextResolver`** dispatches `.style` to `StyleHelpCoordinator` (lexical lookup only)
- **`ResourceSectionIndex`** loads `.style` topics via `flattenStyleTopic` for the interaction feature
- **`EditMenuGroup`** has a Style submenu under Writing Assistance (More Context toggle)
- **`HelpMenuGroup`** has a Style Guide button and Style entries in More Context + Interaction submenus

## Invariants
- Foundation owns the protocol and enums; module 9 owns the coordinators and content
- No module 9 type is imported by Foundation
- All help indexes are actors; access is `await`-ed from `@MainActor`
- Every help kind has a coordinator, an index, a panel view, and a bundled JSON index
