---
module: 9 Resources
status: stable
last_updated: 2026-06-12
last_verified: 2026-06-12
---

## Purpose

Provide shared help content, ASCII art library, completion corpora, image resolution, and other bundled resource assets consumed across Sputnik panels.

## Diagram

```
  Modules 3, 4, 7, 8
        │
        ▼
┌──────────────────────────────────────────┐
│  9 Resources                             │
│                                          │
│  9.1 ASCII Library                       │
│    ASCIILibrary (actor)                  │
│    ASCIIArtRecord — art piece metadata   │
│    ASCIILibraryIndex — index container   │
│                                          │
│  9.2 ASCII Art Help                      │
│    ASCIIArtHelpCoordinator               │
│    ASCIIArtHelpIndex (actor)             │
│    ASCIIArtHelpContent — topic model     │
│    ASCIIArtHelpPanelView                 │
│                                          │
│  9.3 Markdown Help                       │
│    MarkdownHelpCoordinator               │
│    MarkdownHelpIndex (actor)             │
│    MarkdownHelpContent — topic model     │
│    MarkdownHelpPanelView                 │
│                                          │
│  9.4 Html Help                           │
│    HTMLHelpCoordinator                   │
│    HTMLHelpIndex (actor)                 │
│    HTMLHelpContent — topic model         │
│    HTMLHelpPanelView                     │
│    SandboxedHTMLDemo — sandboxed WKWebView│
│                                          │
│  9.5 Grammar Help                        │
│    GrammarHelpCoordinator                │
│    GrammarHelpIndex (actor)              │
│    GrammarHelpContent — topic model      │
│    GrammarHelpPanelView                  │
│    GrammarHelpLookupResult               │
│                                          │
│  9.6 Preview Images                      │
│    PreviewImageResolver (actor) —        │
│    resolves local image refs for         │
│    Markdown/HTML/PDF previews            │
│                                          │
│  Sources/ (shared module 9 types)        │
│    Bundle+ResourcesModule.swift          │
│      Bundle.resourcesModule accessor     │
│    SputnikCompletionCorpus (actor)       │
│      CompletionProviding implementation  │
│    SputnikHelpContextResolver (@MainActor)│
│      HelpContextResolving implementation │
│    SputnikHelpPanel (generic View)       │
│      Reusable tabbed help panel          │
└──────────────────────────────────────────┘
```

## Source Files
| File | Responsibility |
|---|---|
| `Sources/Bundle+ResourcesModule.swift` | Static `Bundle.resourcesModule` accessor for other modules to locate bundled resources |
| `Sources/SputnikCompletionCorpus.swift` | `actor SputnikCompletionCorpus` — concrete `CompletionProviding`; lazily loads weighted completion JSON files per language |
| `Sources/SputnikHelpContextResolver.swift` | `@MainActor SputnikHelpContextResolver` — concrete `HelpContextResolving`; dispatches help lookups to the appropriate sub-module coordinator |
| `Sources/SputnikHelpPanel.swift` | Generic `SputnikHelpPanel<Topic, ContentView>` — reusable tabbed help panel with sidebar, search, and persisted tab state |
| `Sources/9.1 ASCII Library/ASCIIArtRecord.swift` | `ASCIIArtRecord` — data model for a single ASCII art piece (id, title, tags, category, filename) |
| `Sources/9.1 ASCII Library/ASCIILibrary.swift` | `actor ASCIILibrary` — lazy-loads the ASCII art collection; `search(query:)`, `search(category:)`, `art(id:)`, `categories()` |
| `Sources/9.1 ASCII Library/ASCIILibraryIndex.swift` | `ASCIILibraryIndex` — root container decoded from `9.1 ASCII Library/index.json` |
| `Sources/9.2 ASCII art Help/ASCIIArtHelpContent.swift` | `ASCIIArtHelpContent` — topic model with `relatedArtIDs` for `@{art:ID}` placeholders and `exampleCode` |
| `Sources/9.2 ASCII art Help/ASCIIArtHelpCoordinator.swift` | `@MainActor ASCIIArtHelpCoordinator` — handles context-sensitive help lookup from the ASCII art editor |
| `Sources/9.2 ASCII art Help/ASCIIArtHelpIndex.swift` | `actor ASCIIArtHelpIndex` — loads and searches ASCII Art Help topic index |
| `Sources/9.2 ASCII art Help/ASCIIArtHelpPanelView.swift` | `ASCIIArtHelpPanelView` — wraps `SputnikHelpPanel` with ASCII-art-specific rendering (art placeholders, example code) |
| `Sources/9.3 Markdown Help/MarkdownHelpContent.swift` | `MarkdownHelpContent` — topic model with `exampleCode` for Markdown source/rendered toggle |
| `Sources/9.3 Markdown Help/MarkdownHelpCoordinator.swift` | `@MainActor MarkdownHelpCoordinator` — detects Markdown syntax patterns (`## `, `**`, `` ` ``) near cursor to map to help topics |
| `Sources/9.3 Markdown Help/MarkdownHelpIndex.swift` | `actor MarkdownHelpIndex` — loads and searches Markdown Help topic index |
| `Sources/9.3 Markdown Help/MarkdownHelpPanelView.swift` | `@MainActor MarkdownHelpPanelView` — wraps `SputnikHelpPanel` with Markdown body rendering and example toggle |
| `Sources/9.4 Html Help/HTMLHelpContent.swift` | `HTMLHelpContent` — topic model with optional `exampleHTML` for sandboxed live demo |
| `Sources/9.4 Html Help/HTMLHelpCoordinator.swift` | `@MainActor HTMLHelpCoordinator` — maps tag/attribute names (`div`, `href`, `class`) to HTML help topic IDs |
| `Sources/9.4 Html Help/HTMLHelpIndex.swift` | `actor HTMLHelpIndex` — loads and searches HTML Help topic index |
| `Sources/9.4 Html Help/HTMLHelpPanelView.swift` | `HTMLHelpPanelView` — wraps `SputnikHelpPanel` with Markdown body + optional sandboxed `WKWebView` demo via `SandboxedHTMLDemo` |
| `Sources/9.5 Grammar Help/GrammarHelpContent.swift` | `GrammarHelpContent` — topic model with `searchTerms` for fuzzy-match right-click lookup |
| `Sources/9.5 Grammar Help/GrammarHelpCoordinator.swift` | `@MainActor GrammarHelpCoordinator` — dual-panel lookup from editor and Markdown preview; scores by exact/substring/title match |
| `Sources/9.5 Grammar Help/GrammarHelpIndex.swift` | `actor GrammarHelpIndex` — loads and searches Grammar Help topic index; provides `searchByTerm(_:)` for context-sensitive lookup |
| `Sources/9.5 Grammar Help/GrammarHelpPanelView.swift` | `GrammarHelpPanelView` — wraps `SputnikHelpPanel` with ✅/❌ line-level topic body rendering |
| `9.6 Preview Images/PreviewImageResolver.swift` | `actor PreviewImageResolver` — resolves local file-image references; provides downsampled `Data`/`NSImage` bounded by 20 MB and 2000 px caps (not inside `Sources/`) |
| `Package.swift` | SPM manifest — declares dependencies on `FoundationModule` and bundled resource directories |
| `Tests/ResourcesModuleTests.swift` | Unit tests — covers `ASCIIArtRecord`, `PreviewImageResolver`, `SputnikHelpContextResolver`, `SputnikCompletionCorpus`, and all four help indexes |

## Technical Summary

- **Framework(s):** Foundation, AppKit, ImageIO, SwiftUI, WebKit
- **Key types:**
  - `PreviewImageResolver` (`actor`, `9.6 Preview Images/PreviewImageResolver.swift`) — resolves local file-image references relative to a base directory; provides downsampled `Data`/`NSImage` bounded by a 20 MB byte cap and 2000 px pixel cap; rejects absolute paths and `..` escapes; all I/O runs synchronously inside the actor (see source for threading expectations)
  - `SputnikCompletionCorpus` (`actor`, `Sources/SputnikCompletionCorpus.swift`) — concrete `CompletionProviding`; lazily loads weighted completion JSON files from bundled help directories; supports markdown, html, and asciiArt languages; Spelling and Grammar return empty (handled elsewhere)
  - `SputnikHelpContextResolver` (`@MainActor`, `Sources/SputnikHelpContextResolver.swift`) — concrete `HelpContextResolving`; dispatches help lookups to the appropriate sub-module coordinator (`GrammarHelpCoordinator`, `MarkdownHelpCoordinator`, `HTMLHelpCoordinator`, `ASCIIArtHelpCoordinator`)
  - `SputnikHelpPanel` (`View`, `Sources/SputnikHelpPanel.swift`) — generic reusable help panel with sidebar, search bar, tabbed topic browsing, and persisted tab state (`HelpPanelPersistedState`); parameterised over `Topic: HelpTopicProtocol` and topic content builder
  - `ASCIILibrary` (`actor`, `Sources/9.1 ASCII Library/ASCIILibrary.swift`) — lazy-loads ASCII art collection from `index.json`; provides `search(query:)`, `search(category:)`, `art(id:)`, `categories()`; art file content read from disk per `art(id:)` call and never cached beyond caller scope (SR-3)
  - `ASCIIArtRecord` (`Codable`, `Sources/9.1 ASCII Library/ASCIIArtRecord.swift`) — data model for a single ASCII art piece (id, title, tags, category, filename)
  - `Bundle.resourcesModule` — static bundle accessor (`Sources/Bundle+ResourcesModule.swift`) so other modules can locate bundled resources
- **Threading model:** `PreviewImageResolver` is an actor — call with `await` from any context; `SputnikCompletionCorpus` is an actor with lazy-loading on first access; all four help indexes (`GrammarHelpIndex`, `HTMLHelpIndex`, `MarkdownHelpIndex`, `ASCIIArtHelpIndex`) are also actors; `ASCIILibrary` is an actor; `SputnikHelpContextResolver` and all help coordinators are `@MainActor` because they may update observable state or interact with AppKit/WebKit
- **State owned:** Completion indices are lazily loaded and held for app lifetime (negligible RAM — ≤ 60 entries each); help index actors own their topic arrays similarly; `SputnikHelpPanel` persists tab state to `UserDefaults` via `HelpPanelPersistedState` (open tab IDs + active tab ID per panel)
- **Dependencies:** Depends on `FoundationModule` for protocols (`HelpContextResolving`, `CompletionProviding`, `HelpContextQuery`, `CompletionQuery`, `HelpTopicProtocol`, `HelpTopic`), `HelpRequest`, `ErrorReporting`, `AppState`, and shared UI primitives (`SputnikColor`, `SputnikFont`, `SputnikSpacing`)

## Image Resolution Note

`PreviewImageCache.shared` (Foundation, module 2.7 Utilities) is the **canonical image resolver** for preview panels and should be preferred over direct `PreviewImageResolver` calls where caching matters. Each Markdown/HTML preview panel creates its own `PreviewImageResolver` instance to resolve file references, but wrapping those calls through `PreviewImageCache.shared.image(for:loader:)` avoids redundant disk I/O and image decoding when the same image appears in multiple panels or on repeated render passes. See the [2.7 Utilities guide](../2%20Foundation/2.7%20Utilities/guide.md) for full usage details.

## Invariants
- Module 9 **owns no panel-visible state** — it provides resources and context lookups, not views that AppState directly observes (the help panels are sub-panels opened via `AppState.requestedHelpTarget`)
- All four help coordinators (`GrammarHelpCoordinator`, `MarkdownHelpCoordinator`, `HTMLHelpCoordinator`, `ASCIIArtHelpCoordinator`) are `@MainActor` — never called from a background queue without bridging through `await`
- All four help indexes (`GrammarHelpIndex`, `HTMLHelpIndex`, `MarkdownHelpIndex`, `ASCIIArtHelpIndex`) are **actors** — all index access goes through `await`; no direct property access from `@MainActor`
- `ASCIILibrary` is an actor — art file content is read per `art(id:)` call and never cached beyond the caller's scope (SR-3)
- `PreviewImageResolver` rejects absolute paths, `..` escapes, and paths that escape `baseDir` (SR-2, path traversal prevention)
- `allowsContentJavaScript = false` is set on every `WKWebView` configuration created in module 9 (`SandboxedHTMLDemo`) — no JavaScript execution for help snippet rendering (ISS-010)
- `SputnikHelpPanel` persists tab state via `UserDefaults` — persisted state is a cache; corruption is handled by silently starting fresh (no crash on decode failure)

## Known consumers
| Module | Use |
|---|---|
| 3.1 Text Editor | Quick-fix popover help lookups via `SputnikHelpContextResolver` |
| 4 Markdown Preview | Renders help content; resolves embedded images via `PreviewImageResolver` (wrapped in `PreviewImageCache.shared`) |
| 8 HTML Preview | Renders help content; resolves embedded images via `PreviewImageResolver` (wrapped in `PreviewImageCache.shared`) |
| 3 Text Editor | Auto-complete suggestions via `SputnikCompletionCorpus` |
| 5 PDF Viewer | Uses resolved images for thumbnails |
| 2 Foundation (TestingSupport) | Tests use `PreviewImageResolver`-backed image resolution through cache |
| 2.4 UI and UX (`DocumentTabBar`) | Uses `ASCIILibrary.shared` for ASCII art decorations in the tab bar |
| 3.3 ASCII Art | Uses `ASCIILibrary.shared` for the ASCII Studio panel's clipart browser |

## Spec Reference

See original readme.md for the 9 Resources module spec.
