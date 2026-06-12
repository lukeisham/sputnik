---
module: 2.7 Foundation – Utilities
status: active
last_updated: 2026-06-12
---

## Purpose
Provide Foundation-specific utilities: AI monitors, menu helpers, slash-command registry, keychain, and test support. General-purpose utilities (`DebounceTimer`, `RenderThrottle`, `PreviewImageCache`, `ErrorReporting`) were extracted to the `SputnikShared` package (2026-06-12) — see `1 Setup/Module Guides/10 SputnikShared/guide.md`.

## Diagram
```
  Any module
      │
      │  imports Foundation layer
      ▼
┌──────────────────────────────────────────┐
│  Foundation 2.7 Utilities                │
│  (DebounceTimer / RenderThrottle /       │
│   PreviewImageCache / ErrorReporting     │
│   → moved to SputnikShared package)      │
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
│                         @MainActor)                      
│  ┌──────────────────────────────────┐    │
│  │  register([SlashCommand])        │    │
│  │  matches(for prefix:)            │    │
│  │    -> [SlashCommand]             │    │
│  │  (case-insensitive prefix filter │    │
│  │   over in-memory list)           │    │
│  └──────────────────────────────────┘    │
│                                          │
│  SupportingAIMonitor (@Observable        │
│                      @MainActor)         │
│  ┌──────────────────────────────────┐    │
│  │  recordUsage(input:output:win:)  │    │
│  │  reset()                         │    │
│  │  modelName: String (computed)    │    │
│  │                                  │    │
│  │  Accumulates tokens across all   │    │
│  │  Supporting AI resource calls.   │    │
│  │  Writes SupportingAIUsage to     │    │
│  │  AppState.supportingAIUsage      │    │
│  └──────────────────────────────────┘    │
│                                          │
│  MainAIMonitor (@Observable              │
│                 @MainActor)              │
│  ┌──────────────────────────────────┐    │
│  │  observes terminal line output   │    │
│  │  detecs Claude/Ollama sessions   │    │
│  │  setManual(modelName:)           │    │
│  │  updateUsage(used:window:)       │    │
│  │  clear()                         │    │
│  │                                  │    │
│  │  Conforms to TerminalAIObserving │    │
│  │  Writes MainAIState to           │    │
│  │  AppState.mainAIState            │    │
│  └──────────────────────────────────┘    │
│                                          │
│  TerminalAIOutputObserving (protocol)    │
│  ┌──────────────────────────────────┐    │
│  │  observe(line: String)           │    │
│  │                                  │    │
│  │  Foundation-owned protocol.      │    │
│  │  Terminal depends only on this.  │    │
│  └──────────────────────────────────┘    │
│                                          │
│  ─── Moved to SputnikShared (2026-06-12) ───
│  DebounceTimer / RenderThrottle /        │
│  PreviewImageCache / ErrorReporting      │
│  See: 1 Setup/Module Guides/10 SputnikShared/guide.md
│                                          │
│  TestingSupport                          │
│  ┌──────────────────────────────────┐    │
│  │  MockInterPanelRouter            │
│  │    open(_:) / close(_:) /        │
│  │    syncDirectory(_:) /           │
│  │    moveActiveTabToNewWindow()    │
│  │    shouldSucceed: Bool           │
│  │                                  │
│  │  MockAppState                    │
│  │    isProcessing: Bool            │
│  │    beginProcessing() /           │
│  │    endProcessing()               │
│  │                                  │
│  │  MockWindowState                 │
│  │    openDocument(_:) /            │
│  │    closeDocument(_:) /           │
│  │    moveDocument(from:to:)        │
│  └──────────────────────────────────┘    │
└──────────────────────────────────────────┘
```

## Technical Summary
- **Framework(s):** Foundation (Swift Concurrency), AppKit
- **Moved to SputnikShared:** `DebounceTimer`, `RenderThrottle`, `PreviewImageCache`, `ErrorReporting` — see `SputnikShared/Sources/` and `1 Setup/Module Guides/10 SputnikShared/guide.md`.
- **Key types remaining in Foundation:**
  - *(DebounceTimer moved → SputnikShared)*
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
  - `TerminalAIOutputObserving` (protocol, `2 Foundation/2.7 Utilities/MainAIMonitor.swift`) — Foundation-owned protocol with `func observe(line: String)`; Terminal module calls this when a new output line arrives so Foundation can detect Main AI sessions without Terminal importing the monitor implementation directly (SR-1); `MainAIMonitor` conforms to this protocol
  - `MainAIMonitor` (`@Observable @MainActor`, `2 Foundation/2.7 Utilities/MainAIMonitor.swift`) — monitors terminal output to detect and track the Main AI (user-loaded AI in the terminal, e.g. Claude Code CLI, Ollama); receives output lines via `TerminalAIOutputObserving.observe(line:)`; detects Claude sessions via `"✻ Welcome to Claude Code"`, Ollama via `"ollama run "` and `"loaded model: "`; resolves exact Claude model name from `~/.claude/settings.json`; polls `~/.claude/stats.json` for usage metrics (migrated from `ClaudeStatusLineReader`); exposes `setManual(modelName:)` for unknown AIs, `updateUsage(usedTokens:contextWindow:)` for usage updates, and `clear()` to reset detection; writes `MainAIState` to `AppState.mainAIState` exclusively (SR-1); created in `SputnikApp`, injected via `.environment(mainAIMonitor)`, and registered as `aiOutputObserver` on `TerminalManager` via `TerminalView.onAppear`
  - `SupportingAIMonitor` (`@Observable @MainActor`, `2 Foundation/2.7 Utilities/SupportingAIMonitor.swift`) — single accountant for all Supporting AI resource-feature API calls (help lookups, completions, More Context); accumulates `totalTokensSinceLaunch` across the app session; `recordUsage(inputTokens:outputTokens:contextWindow:)` is called by any resource feature after a Supporting AI API response; writes `SupportingAIUsage` to `AppState.supportingAIUsage` exclusively (SR-1); `modelName` computed from `SettingsStore.supportingAIConfig.modelName`; `reset()` zeroes the accumulator (called at app launch); created in `SputnikApp`, injected via `.environment(supportingAIMonitor)`
  - *(ErrorReporting moved → SputnikShared)*
  - *(PreviewImageCache moved → SputnikShared)*
  - *(RenderThrottle moved → SputnikShared)*
  - `TestingSupport` (`2 Foundation/2.7 Utilities/TestingSupport.swift`) — three mock implementations for unit testing module logic without real panels or state:
    - `MockInterPanelRouter`: conforms to `InterPanelRouter`; records calls to `open(_:)`, `close(_:)`, `syncDirectory(_:)`, `moveActiveTabToNewWindow()` in tracked arrays/counters; `shouldSucceed` controls whether `moveActiveTabToNewWindow()` returns a `UUID` or `nil`; `events` returns a no-op `AsyncStream`
    - `MockAppState`: tracks `isProcessing` via `beginProcessing()`/`endProcessing()`; holds `activeDocument`, `activeWindowID`, `requestedHelpTarget`, and `contextUsageForTesting` for assertions
    - `MockWindowState`: tracks `openDocuments`, `activeDocumentID`, `panelLayout`, `panelSizes`; records `moveDocumentCalls` and `closeDocumentCalls`; `openDocument(_:)` appends and sets `activeDocumentID`; `closeDocument(_:)` removes and returns the session or `nil`
- **Threading model:**
  - `ClosureMenuItem` and `MoreContextMenu` are `@MainActor` — menu construction and activation happen on the main thread
  - `HelpContextResolving.resolve` is `async` — the resolver runs the coordinator lookup (which may be actor-isolated) inside a `Task`; the host's `onRequest` sink writes to `AppState.requestedHelpTarget` on `@MainActor`
  - `HelpContextQuery` is `Sendable` — safe to pass across actor boundaries
- **Data flow:** Host captures selection → calls `MoreContextMenu.items(...)` → builds one `ClosureMenuItem` per candidate kind → user clicks item → `Task` resolves query via `resolver.resolve(query)` → on completion, `onRequest(request)` writes to `AppState.requestedHelpTarget`
- **State owned:** None — these are stateless utilities. `ClosureMenuItem` holds its closure; `MoreContextMenu` is an uninstantiable enum. `ErrorReporting` owns its ring buffer (actor-isolated). `PreviewImageCache` owns the `NSCache` (actor-isolated). `RenderThrottle` owns the `DebounceTimer` and generation counter.
- **Dependencies:** None on other Sputnik modules beyond Foundation types `HelpTopic` and `HelpRequest` (2.4 UI/UX). No dependency on module 9 (SR-1). Foundation 2.7 now depends on `SputnikShared` (for `ErrorReporting` used in `MainAIMonitor`).

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
| 2.3 AI Settings (F-3) | `SupportingAIMonitor` injects `SupportingAIUsage` into `AppState` for live metrics display in `SupportingAISettingsView` |
| 2.4 Status Bar (F-5) | `MainAIMonitor` provides `MainAIState` for the Main AI model name + CTX % segment in `StatusBarView` |
| 7 Terminal | Calls `TerminalAIOutputObserving.observe(line:)` for each decoded output line; depends only on the protocol, not `MainAIMonitor` directly (SR-1) |
| 3 Text Editor / 4 Markdown Preview / 8 HTML Preview / 9 Resources | Resource-feature code calls `SupportingAIMonitor.recordUsage(inputTokens:outputTokens:contextWindow:)` after each Supporting AI API response |
| All modules | `ErrorReporting.shared.log(...)` / `report(...)` for non-fatal errors; ring buffer for future telemetry |
| 4 Markdown Preview / 8 HTML Preview | `PreviewImageCache.shared.image(for:loader:)` to avoid redundant image decoding across preview panels |
| 4 Markdown Preview | `RenderThrottle.throttle(render:)` to coalesce Markdown re-renders during fast typing |
| 2 Foundation (Tests) | `MockInterPanelRouter`, `MockAppState`, `MockWindowState` for unit tests that verify module logic without real state |

## Spec Reference
> `DebounceTimer` has no direct spec bullet — it is an implementation utility inferred from the debouncing requirements described across multiple sub-modules:

```
  10. ASCII art support (Inline Suggestions / Ghost Text, Debouncing, Block Completion)
  11. HTML language support (Inline Suggestions / Ghost Text, Debouncing)
  12. Markdown language support (Inline Suggestions / Ghost Text, Debouncing)
```

> The More Context utility is derived from the "More Context" right-click lookup gesture specified in the Text Editor, Markdown Preview, and HTML Preview module specs.
