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
│                                          │
│  CompletionQuery (Sendable)              │
│  ┌──────────────────────────────────┐    │
│  │  language: WritingAssistLanguage │    │
│  │  prefix: String                  │    │
│  │  fullText: String                │    │
│  │  cursorOffset: Int               │    │
│  │  limit: Int                      │    │
│  └──────────────────────────────────┘    │
│                                          │
│  CompletionProviding (protocol)          │
│  ┌──────────────────────────────────┐    │
│  │  completions(CompletionQuery)    │    │
│  │    async -> [String]             │    │
│  └──────────────────────────────────┘    │
│                                          │
│  KeychainService (@MainActor)            │
│  ┌──────────────────────────────────┐    │
│  │  save(key:service:)              │    │
│  │  load(service:) -> String?       │    │
│  │  delete(service:)                │    │
│  │                                  │    │
│  │  Security.framework SecItem* API │    │
│  │  service: "com.sputnik.aiAPIKey" │    │
│  └──────────────────────────────────┘    │
│                                          │
│  ProcessMonitor (@Observable @MainActor) │
│  ┌──────────────────────────────────┐    │
│  │  ramMB: Int                      │    │
│  │  cpuPercent: Double              │    │
│  │                                  │    │
│  │  start() → Task(priority:.bg)    │    │
│  │    loop: mach_task_basic_info    │    │
│  │          thread_basic_info       │    │
│  │          sleep 2 s               │    │
│  │  stop()  → cancel task           │    │
│  └──────────────────────────────────┘    │
│                                          │
│  SlashCommand (Sendable)                 │
│  ┌──────────────────────────────────┐    │
│  │  id, label, detail               │    │
│  │  category, insert: String        │    │
│  └──────────────────────────────────┘    │
│                                          │
│  SlashCommandRegistry (@Observable       │
│                         @MainActor)      │
│  ┌──────────────────────────────────┐    │
│  │  register([SlashCommand])        │    │
│  │  matches(for prefix:)            │    │
│  │    -> [SlashCommand]             │    │
│  │  (case-insensitive prefix filter │    │
│  │   over in-memory list)           │    │
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
  - `CompletionQuery` — `Sendable` value type: `language: WritingAssistLanguage`, `prefix: String`, `fullText: String`, `cursorOffset: Int`, `limit: Int`; content-agnostic completion request passed from editor providers to the corpus (SR-1)
  - `CompletionProviding` — `Sendable` protocol with `func completions(_ query: CompletionQuery) async -> [String]`; Foundation owns the protocol, module 9 provides `SputnikCompletionCorpus`; module 3 providers depend only on the protocol (SR-1)
  - `KeychainService` (`@MainActor`, `2 Foundation/2.7 Utilities/KeychainService.swift`) — thin wrapper around `Security.framework` `SecItem*` C API; exposes `save(key:service:)`, `load(service:) -> String?`, and `delete(service:)`; service label `"com.sputnik.aiAPIKey"`; all methods are synchronous (Keychain C API has no async variant — documented at each call site per MR-3); every `OSStatus` non-`errSecSuccess` result is handled; `CFTypeRef` return is safely cast, never force-unwrapped; resolves ISS-014
  - `SlashCommand` (`Sendable Identifiable`, `2 Foundation/2.7 Utilities/SlashCommand.swift`) — value type describing one autocomplete entry: `id: String` (e.g. `"markdown.heading1"`), `label: String` (shown in list), `detail: String` (short description), `category: String` (popup section header), `insert: String` (text substituted at the trigger point); Foundation owns the type, consumer modules supply the content (SR-1)
  - `SlashCommandRegistry` (`@Observable @MainActor`, `2 Foundation/2.7 Utilities/SlashCommandRegistry.swift`) — `register(_ commands: [SlashCommand])` called by each module at launch; `matches(for prefix: String) -> [SlashCommand]` performs case-insensitive prefix filtering over the in-memory list; synchronous (in-memory filter — no async needed); `///` DocC comments on both public methods; consumer modules register their own command sets so Foundation owns the interface, not the content (SR-1)
  - `ProcessMonitor` (`@Observable @MainActor`, `2 Foundation/2.7 Utilities/ProcessMonitor.swift`) — polls the Sputnik process's own resource usage every 2 seconds; exposes `ramMB: Int` (resident-set size via `mach_task_basic_info`) and `cpuPercent: Double` (CPU across all threads via `thread_basic_info`); `start()` launches a `Task(priority: .background)` polling loop that marshals results to `@MainActor` via `await MainActor.run { }`; `stop()` cancels the task; polling loop uses `[weak self]` to avoid retaining the monitor for app lifetime; created at launch in `AppDelegate` and injected into the environment via `.environment(processMonitor)`; resolves ISS-013
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
| 2.3 AI Settings (F-3) | Store and retrieve API key in macOS Keychain via `KeychainService` |
| 2.4 Status Bar (F-5) | RAM and CPU % readings consumed by `StatusBarView` from `ProcessMonitor` |
| 3.1 Text Editor (F-7) | Registers Markdown / HTML / ASCII slash-command sets via `SlashCommandRegistry.register(_:)` at module init |
| 10 Scratchpad (F-7) | Registers General slash-command set; `ScratchpadTextView` calls `registry.matches(for:)` on `/` keypress |

## Spec Reference
> `DebounceTimer` has no direct spec bullet — it is an implementation utility inferred from the debouncing requirements described across multiple sub-modules:

```
  10. ASCII art support (Inline Suggestions / Ghost Text, Debouncing, Block Completion)
  11. HTML language support (Inline Suggestions / Ghost Text, Debouncing)
  12. Markdown language support (Inline Suggestions / Ghost Text, Debouncing)
```

> The More Context utility is derived from the "More Context" right-click lookup gesture specified in the Text Editor, Markdown Preview, and HTML Preview module specs.
