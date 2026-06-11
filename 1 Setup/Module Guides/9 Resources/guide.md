---
module: 9 Resources
status: active
last_updated: 2026-06-11
---

## Purpose

Provide shared help content, ASCII art library, completion corpora, image resolution, and other bundled resource assets consumed across Sputnik panels.

## Diagram

```
  Modules 3, 4, 7, 8
        │
        ▼
┌──────────────────────────────────────┐
│  9 Resources                         │
│                                      │
│  9.1 ASCII Library                   │
│    ASCII art character sets          │
│                                      │
│  9.2 ASCII Art Help                  │
│    ASCII art help topics + corpus    │
│                                      │
│  9.3 Markdown Help                   │
│    Markdown help topics + corpus     │
│                                      │
│  9.4 Html Help                       │
│    HTML help topics + corpus         │
│                                      │
│  9.5 Grammar Help                    │
│    Grammar help topics               │
│                                      │
│  9.6 Preview Images                  │
│    PreviewImageResolver —            │
│    resolves local image refs for     │
│    Markdown/HTML/PDF previews        │
│                                      │
│  Bundle+ResourcesModule.swift        │
│    Bundle.resourcesModule accessor   │
│                                      │
│  SputnikCompletionCorpus             │
│    CompletionProviding implementation│
│                                      │
│  SputnikHelpContextResolver          │
│    HelpContextResolving implementation│
│                                      │
│  SputnikHelpPanel (module 9)         │
└──────────────────────────────────────┘
```

## Technical Summary

- **Framework(s):** Foundation, AppKit, ImageIO
- **Key types:**
  - `PreviewImageResolver` (`actor`, `9 Resources/9.6 Preview Images/PreviewImageResolver.swift`) — resolves local file-image references relative to a base directory; provides downsampled `Data`/`NSImage` bounded by a 20 MB byte cap and 2000 px pixel cap; rejects absolute paths and `..` escapes; all I/O runs synchronously inside the actor (see source for threading expectations)
  - `SputnikCompletionCorpus` (`actor`, `9 Resources/SputnikCompletionCorpus.swift`) — concrete `CompletionProviding`; lazily loads weighted completion JSON files from bundled help directories; supports markdown, html, and asciiArt languages; Spelling and Grammar return empty (handled elsewhere)
  - `SputnikHelpContextResolver` (`@MainActor`, `9 Resources/SputnikHelpContextResolver.swift`) — concrete `HelpContextResolving`; dispatches help lookups to the appropriate sub-module coordinator (`GrammarHelpCoordinator`, `MarkdownHelpCoordinator`, `HTMLHelpCoordinator`, `ASCIIArtHelpCoordinator`)
  - `Bundle.resourcesModule` — static bundle accessor so other modules can locate bundled resources
- **Threading model:** `PreviewImageResolver` is an actor — call with `await` from any context; `SputnikCompletionCorpus` is an actor with lazy-loading on first access; `SputnikHelpContextResolver` is `@MainActor` because coordinators may update observable state
- **State owned:** Completion indices are lazily loaded and held for app lifetime (negligible RAM — ≤ 60 entries each); help coordinators own their topic indices similarly
- **Dependencies:** Depends on `FoundationModule` for protocols (`HelpContextResolving`, `CompletionProviding`, `HelpContextQuery`, `CompletionQuery`, etc.), `HelpTopic`, `HelpRequest`, and `ErrorReporting`

## Image Resolution Note

`PreviewImageCache.shared` (Foundation, module 2.7 Utilities) is the **canonical image resolver** for preview panels and should be preferred over direct `PreviewImageResolver` calls where caching matters. Each Markdown/HTML preview panel creates its own `PreviewImageResolver` instance to resolve file references, but wrapping those calls through `PreviewImageCache.shared.image(for:loader:)` avoids redundant disk I/O and image decoding when the same image appears in multiple panels or on repeated render passes. See the [2.7 Utilities guide](../2%20Foundation/2.7%20Utilities/guide.md) for full usage details.

## Known consumers
| Module | Use |
|---|---|
| 3.1 Text Editor | Quick-fix popover help lookups via `SputnikHelpContextResolver` |
| 4 Markdown Preview | Renders help content; resolves embedded images via `PreviewImageResolver` (wrapped in `PreviewImageCache.shared`) |
| 8 HTML Preview | Renders help content; resolves embedded images via `PreviewImageResolver` (wrapped in `PreviewImageCache.shared`) |
| 3 Text Editor | Auto-complete suggestions via `SputnikCompletionCorpus` |
| 5 PDF Viewer | Uses resolved images for thumbnails |
| 2 Foundation (TestingSupport) | Tests use `PreviewImageResolver`-backed image resolution through cache |

## Spec Reference

See original readme.md for the 9 Resources module spec.
