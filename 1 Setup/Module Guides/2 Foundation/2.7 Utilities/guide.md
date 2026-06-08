---
module: 2.7 Foundation – Utilities
status: active
last_updated: 2026-06-08
---

## Purpose
Provide small, general-purpose utilities that have no module-specific logic and could be used by any module in Sputnik — keeping shared infrastructure out of module internals and avoiding duplication.

## Diagram
```
  Any module
      │
      │  imports Foundation layer
      ▼
┌─────────────────────────────────┐
│  Foundation 2.7 Utilities       │
│                                 │
│  DebounceTimer                  │
│  ┌──────────────────────────┐   │
│  │  schedule(delay:work:)   │   │
│  │  cancel()                │   │
│  │                          │   │
│  │  async Task.sleep(delay) │   │
│  │  → if not cancelled      │   │
│  │    → run work()          │   │
│  └──────────────────────────┘   │
│                                 │
│  (future utilities added here)  │
└─────────────────────────────────┘
```

## Technical Summary
- **Framework(s):** Foundation (Swift Concurrency)
- **Key types:**
  - `DebounceTimer` — wraps a cancellable `Task` that sleeps for a configurable interval then executes a closure; calling `schedule` again before the sleep expires cancels the previous task and starts a fresh one; calling `cancel()` discards the pending work without running it <!-- assumed -->
- **Threading model:** `DebounceTimer` itself is `@MainActor`-safe — the work closure runs on whichever actor the caller is on; the internal `Task` uses `Task.sleep` from Swift Concurrency (no `DispatchQueue`), so it composes cleanly with `async/await` callers
- **Data flow:** caller calls `schedule(delay:work:)` → any prior pending `Task` is cancelled → new `Task` starts sleeping → if sleep completes without cancellation → `work()` executes
- **State owned:** the single active `Task?` token per `DebounceTimer` instance; no shared global state
- **Dependencies:** none — this module has no dependencies on other Sputnik modules
- **Failure modes:** `work` closure throws → error propagates to the `Task`; callers that care must wrap `schedule` in a `try`-aware variant or handle errors inside the closure; `Task` cancellation before sleep completes → `CancellationError` is swallowed internally, no visible effect

## Known consumers
| Module | Use |
|---|---|
| 3.1 Text (and 3.2–3.5 via 3.1) | Debounce ghost-text suggestion requests on keypress |

## Spec Reference
> `DebounceTimer` has no direct spec bullet — it is an implementation utility inferred from the debouncing requirements described across multiple sub-modules:

```
  10. ASCII art support (Inline Suggestions / Ghost Text, Debouncing, Block Completion)
  11. HTML language support (Inline Suggestions / Ghost Text, Debouncing)
  12. Markdown language support (Inline Suggestions / Ghost Text, Debouncing)
```
