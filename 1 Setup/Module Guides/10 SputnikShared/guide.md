---
module: 10 SputnikShared
status: stable
last_updated: 2026-06-12
last_verified: 2026-06-12
---

## Purpose
General-purpose utilities shared across all Sputnik modules — debouncing, render coalescing, image caching, and error logging. No dependency on any Sputnik module; imported by any module that needs one of these primitives.

## Diagram
```
  SputnikShared (no upstream Sputnik deps)
  ┌──────────────────────────────────────────┐
  │                                          │
  │  DebounceTimer (@MainActor)              │
  │  ┌──────────────────────────────────┐    │
  │  │  schedule(delay:work:)           │    │
  │  │  cancel()                        │    │
  │  │                                  │    │
  │  │  Cancellable Task.sleep → work() │    │
  │  │  All callers are @MainActor      │    │
  │  └──────────────────────────────────┘    │
  │                                          │
  │  RenderThrottle (@MainActor)             │
  │  ┌──────────────────────────────────┐    │
  │  │  init(delay:)                    │    │
  │  │  throttle(render:)               │    │
  │  │  cancel()                        │    │
  │  │  delay: TimeInterval (0.1 def)   │    │
  │  │                                  │    │
  │  │  wraps DebounceTimer +           │    │
  │  │  generation coalescing           │    │
  │  └──────────────────────────────────┘    │
  │                                          │
  │  PreviewImageCache (actor)               │
  │  ┌──────────────────────────────────┐    │
  │  │  shared (singleton)              │    │
  │  │  image(for:loader:) -> NSImage?  │    │
  │  │  set(_:for:)                     │    │
  │  │  invalidate()                    │    │
  │  │  invalidate(for:)                │    │
  │  │  maxDimension: CGFloat (2048)    │    │
  │  │                                  │    │
  │  │  NSCache<NSURL, NSImage> +       │    │
  │  │  generation-based invalidation   │    │
  │  │  auto-downsample on cache fill   │    │
  │  └──────────────────────────────────┘    │
  │                                          │
  │  ErrorReporting (actor)                  │
  │  ┌──────────────────────────────────┐    │
  │  │  shared (singleton)              │    │
  │  │  log(message:category:)          │    │
  │  │  report(error:category:)         │    │
  │  │  recentEntries(limit:) -> [Str]  │    │
  │  │                                  │    │
  │  │  os_log + ring buffer (1000 max) │    │
  │  │  Thread-safe via actor isolation │    │
  │  └──────────────────────────────────┘    │
  │                                          │
  └──────────────────────────────────────────┘
         ▲         ▲         ▲        ▲
  Foundation  TextEditor  Markdown  Terminal
  (+ PDF, FileTree, HTMLPreview)
```

## Source Files
| File | Responsibility |
|---|---|
| `Sources/DebounceTimer.swift` | `@MainActor` debounce via `Task.sleep`; cancels pending work on re-schedule |
| `Sources/RenderThrottle.swift` | `@MainActor` generation-based coalescer wrapping `DebounceTimer` |
| `Sources/PreviewImageCache.swift` | Actor-isolated `NSCache` for preview images; auto-downsamples to `maxDimension` |
| `Sources/ErrorReporting.swift` | Actor-isolated ring buffer + `os_log` error/warning sink |

## Technical Summary
- **Framework(s):** Foundation, AppKit (`NSCache`, `NSImage`), `os.log`
- **Threading model:**
  - `DebounceTimer` and `RenderThrottle` are `@MainActor` — call sites are all `@MainActor` view models or AppKit view subclasses on the main thread
  - `PreviewImageCache` is an `actor` — call with `await`; cache-miss image loading is dispatched to a `.utility` background task via `Task.detached`
  - `ErrorReporting` is an `actor` — call with `await` from any concurrency context
- **Key invariants:**
  - `DebounceTimer` and `RenderThrottle` must only be created and called from `@MainActor` contexts
  - `PreviewImageCache.shared` and `ErrorReporting.shared` are safe to call from any context via `await`
  - No `@unchecked Sendable` — actor isolation and `@MainActor` provide compile-verified thread safety
  - No dependency on any Sputnik module — zero import of Foundation/TextEditor/etc.
- **Package structure:** `SputnikShared/Package.swift` declares a single `SputnikShared` library target at `Sources/`

## Consumers
| Module | Uses |
|---|---|
| 2 Foundation (MainAIMonitor) | `ErrorReporting.shared.log/report` |
| 3 Text Editor (language providers, EditorView) | `DebounceTimer` for ghost-text debounce |
| 4 Markdown Preview | `RenderThrottle` for render coalescing; `PreviewImageCache` for image caching |
| 5 PDF Viewer | `PreviewImageCache` for thumbnail caching |
| 6 Project File Tree | `DebounceTimer` for tree refresh debounce |
| 7 Terminal | `RenderThrottle` for output render coalescing |
| 8 HTML Preview | `RenderThrottle` for render coalescing |

## Invariants
- This package has no imports of any other Sputnik package — it is the dependency floor
- `DebounceTimer` and `RenderThrottle` are `@MainActor`; do not use them from non-`@MainActor` contexts
- Actors (`PreviewImageCache`, `ErrorReporting`) never use `@unchecked Sendable`
