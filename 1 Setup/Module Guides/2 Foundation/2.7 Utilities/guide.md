---
module: 2.7 Foundation – Utilities
status: active
last_updated: 2026-06-09
---

## Purpose
Provide small, general-purpose utilities that have no module-specific logic and could be used by any module in Sputnik — keeping shared infrastructure out of module internals and avoiding duplication.

## Diagram
```
  Any module
      │
      │  imports Foundation layer
      ▼
┌──────────────────────────────────────────┐
│  Foundation 2.7 Utilities                │
│                                          │
│  DebounceTimer                           │
│  ┌──────────────────────────────────┐    │
│  │  schedule(delay:work:)           │    │
│  │  cancel()                        │    │
│  │                                  │    │
│  │  async Task.sleep(delay)         │    │
│  │  → if not cancelled → run work()│    │
│  └──────────────────────────────────┘    │
│                                          │
│  ClosureMenuItem                         │
│  ┌──────────────────────────────────┐    │
│  │  NSMenuItem subclass that runs   │    │
│  │  a stored () -> Void on action   │    │
│  │  (self.target / self.action)     │    │
│  └──────────────────────────────────┘    │
│                                          │
│  HelpContextQuery (Sendable)             │
│  ┌──────────────────────────────────┐    │
│  │  kind: HelpTopic                 │    │
│  │  selectedText: String            │    │
│  │  fullText: String                │    │
│  │  cursorOffset: Int               │    │
│  └──────────────────────────────────┘    │
│                                          │
│  HelpContextResolving (protocol)         │
│  ┌──────────────────────────────────┐    │
│  │  resolve(HelpContextQuery) ->    │    │
│  │    HelpRequest?                  │    │
│  └──────────────────────────────────┘    │
│                                          │
│  MoreContextMenu (builder enum)          │
│  ┌──────────────────────────────────┐    │
│  │  items(forSelectedText:kinds:    │    │
│  │        fullText:cursorOffset:    │    │
│  │        resolver:onRequest:)      │    │
│  │  → [NSMenuItem]                  │    │
│  │  (empty when selection blank)    │    │
│  └──────────────────────────────────┘    │
└──────────────────────────────────────────┘
```

## Technical Summary
- **Framework(s):** Foundation (Swift Concurrency), AppKit
- **Key types:**
  - `DebounceTimer` — wraps a cancellable `Task` that sleeps for a configurable interval then executes a closure; calling `schedule` again before the sleep expires cancels the previous task and starts a fresh one; calling `cancel()` discards the pending work without running it
  - `ClosureMenuItem` — `@MainActor NSMenuItem` subclass that runs a stored `() -> Void` on activation via its own `target`/`action`; avoids each host wiring `@objc` selectors
  - `HelpContextQuery` — `Sendable` value type describing a user's current selection and context: the target `HelpTopic` kind, selected text, full document text, and cursor offset; content-agnostic — Foundation owns the query type, not the orchestration (SR-1)
  - `HelpContextResolving` — `Sendable` protocol with `func resolve(_ query: HelpContextQuery) async -> HelpRequest?`; content-agnostic seam for resolving a text selection to a help topic; Foundation owns the protocol, module 9 provides the concrete resolver (SR-1)
  - `MoreContextMenu` — `@MainActor` builder enum; static `items(forSelectedText:kinds:fullText:cursorOffset:resolver:onRequest:) -> [NSMenuItem]` creates one `ClosureMenuItem` per candidate `HelpTopic` kind titled `"More Context: <kind.title>"`; returns `[]` when selection is empty/whitespace; on activation, runs the resolver in a `Task` and routes the result through the caller-supplied `onRequest` sink
- **Threading model:**
  - `ClosureMenuItem` and `MoreContextMenu` are `@MainActor` — menu construction and activation happen on the main thread
  - `HelpContextResolving.resolve` is `async` — the resolver runs the coordinator lookup (which may be actor-isolated) inside a `Task`; the host's `onRequest` sink writes to `AppState.requestedHelpTarget` on `@MainActor`
  - `HelpContextQuery` is `Sendable` — safe to pass across actor boundaries
- **Data flow:** Host captures selection → calls `MoreContextMenu.items(...)` → builds one `ClosureMenuItem` per candidate kind → user clicks item → `Task` resolves query via `resolver.resolve(query)` → on completion, `onRequest(request)` writes to `AppState.requestedHelpTarget`
- **State owned:** None — these are stateless utilities. `ClosureMenuItem` holds its closure; `MoreContextMenu` is an uninstantiable enum.
- **Dependencies:** None on other Sputnik modules beyond Foundation types `HelpTopic` and `HelpRequest` (2.4 UI/UX). No dependency on module 9 (SR-1).

## Known consumers
| Module | Use |
|---|---|
| 3.1 Text (and 3.2–3.5 via 3.1) | Debounce ghost-text suggestion requests on keypress |
| 3.1 Text Editor | More Context right-click menu (single kind based on editor mode: grammar/markdown/html/asciiArt) |
| 4 Markdown Preview | More Context right-click menu (two kinds: .grammar + .markdown) |
| 8 HTML Preview | More Context right-click menu (two kinds: .grammar + .html) |

## Spec Reference
> `DebounceTimer` has no direct spec bullet — it is an implementation utility inferred from the debouncing requirements described across multiple sub-modules:

```
  10. ASCII art support (Inline Suggestions / Ghost Text, Debouncing, Block Completion)
  11. HTML language support (Inline Suggestions / Ghost Text, Debouncing)
  12. Markdown language support (Inline Suggestions / Ghost Text, Debouncing)
```

> The More Context utility is derived from the "More Context" right-click lookup gesture specified in the Text Editor, Markdown Preview, and HTML Preview module specs.
