---
plan: Foundation Sendable sweep and utility extraction
status: new
created: 2026-06-12
author: Zed (code analysis)
issues: ISS-060 (foundation sendable), ISS-060 (utility extraction)
---

## Summary

Two architectural issues in Foundation:

1. **`@unchecked Sendable` sweep (beyond AppState):** Nine classes use `@unchecked Sendable`. A plan exists for `AppState` only (`2026-06-11 Make AppState Sendable-safe.md`). The remaining eight need the same treatment — either remove the conformance entirely (`@MainActor` classes) or replace it with proper Sendable guarantees (actors).

2. **Utility extraction to a shared target:** `DebounceTimer`, `RenderThrottle`, `PreviewImageCache`, and `ErrorReporting` are general-purpose utilities that have nothing to do with state management or inter-panel routing. They should live in a dedicated `SputnikShared` target so Foundation can focus on its actual role.

## Existing plans (not duplicated here)

| Issue | Plan | File |
|---|---|---|
| ISS-051 — Extract `SettingsStore.loadAll()` | ✅ Exists | `Plans New/2026-06-11 Extract loadAll() from SettingsStore.md` |
| ISS-056 — EditorViewModel dependency injection | ✅ Exists | `Plans New/2026-06-12 Fix EditorViewModel dependency injection and incremental highlighting.md` |
| ISS-052 — AppState Sendable-safe | ✅ Exists | `Plans New/2026-06-11 Make AppState Sendable-safe.md` |

---

## Part 1: `@unchecked Sendable` sweep

### Current State

| Class | Isolation | `@unchecked Sendable`? | Plan exists? |
|---|---|---|---|
| `AppState` | `@MainActor` | ✅ | ✅ `2026-06-11 Make AppState Sendable-safe.md` |
| `SettingsStore` | `@MainActor` | ✅ | ❌ Not yet |
| `WindowState` | `@MainActor` | ✅ | ❌ Not yet |
| `SupportingAIMonitor` | `@MainActor` | ✅ | ❌ Not yet |
| `DebounceTimer` | None (plain class) | ✅ | ❌ Not yet |
| `RenderThrottle` | None (plain class) | ✅ | ❌ Not yet |
| `ErrorReporting` | `actor` | ✅ | ❌ Not yet |
| `PreviewImageCache` | `actor` | ✅ | ❌ Not yet |
| `FileWatcher` (module 3) | `NSObject` + `NSFilePresenter` | ✅ | ❌ Not yet |
| `FileSystemWatcher` (module 6) | `NSObject` + `NSFilePresenter` | ✅ | ❌ Not yet |

### Approach by category

**Category A — `@MainActor` classes (`SettingsStore`, `WindowState`, `SupportingAIMonitor`):**
These are `@MainActor`-isolated, so they do not need `Sendable` conformance. Remove `@unchecked Sendable` and add a doc comment explaining that `@MainActor` provides the safety.

```swift
// Before:
@Observable @MainActor public final class SettingsStore: @unchecked Sendable {

// After:
@Observable @MainActor public final class SettingsStore {
```

Same pattern as the existing AppState plan. If removing it breaks the build, each broken call site reveals a real data-race risk that should be fixed (not suppressed).

**Category B — Plain classes (`DebounceTimer`, `RenderThrottle`):**
These are not `@MainActor`. They hold a `Task<Void, Never>?` which is `Sendable`. The `@unchecked Sendable` is needed because the stored `Task` reference is mutable and the compiler cannot prove thread safety. 

Solution: Move to the shared target and use actor isolation or `@MainActor`:

- **`DebounceTimer`** is only used from `@MainActor` contexts (all call sites are in `@MainActor` view models). Add `@MainActor` to the class, remove `@unchecked`.
- **`RenderThrottle`** is only used from `@MainActor` contexts. Same treatment.

```swift
// Before:
public final class DebounceTimer: @unchecked Sendable {

// After:
@MainActor
public final class DebounceTimer {
```

**Category C — Actors (`ErrorReporting`, `PreviewImageCache`):**
An actor with `@unchecked Sendable` defeats the purpose of using an actor — the entire point of actor isolation is compiler-enforced Sendable safety. Remove `@unchecked Sendable` from actors entirely. If actor-isolated properties are all `Sendable`, the conformance is automatic.

- **`ErrorReporting`** stores `LogEntry: Sendable` in a private ring buffer — all `Sendable`. Remove `@unchecked`.
- **`PreviewImageCache`** stores `[URL: NSImage]` where `NSImage` is not `Sendable`. For an actor, the conformance should be automatic since the non-Sendable dictionary is actor-isolated. Remove `@unchecked`.

```swift
// Before:
public actor ErrorReporting: @unchecked Sendable {

// After:
public actor ErrorReporting {
```

**Category D — `NSObject` subclasses (`FileWatcher`, `FileSystemWatcher`):**
These conform to `NSFilePresenter` which requires `NSObject`. The `@unchecked Sendable` is needed because `NSObject` subclasses cannot be `Sendable` in general. These are legitimate uses of `@unchecked` — they need a documented justification rather than removal.

```swift
public final class FileWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    // Justification: NSFilePresenter requires NSObject, and Sendable conformance
    // cannot be verified for ObjC-bridged types. All mutable state is accessed
    // from @MainActor callbacks, making this safe in practice.
```

Add the justification comment but keep `@unchecked`. These are the one category where `@unchecked` is genuinely needed.

---

## Part 2: Utility extraction to shared target

### Current State

Four utility types live in `2 Foundation/2.7 Utilities/` but have nothing to do with Foundation's mission (state management, inter-panel routing, settings, persistence):

| File | Used by | Role |
|---|---|---|
| `DebounceTimer.swift` | 3.1 Text, 4 Markdown Preview, 6 File Tree | Generic debounced scheduling |
| `RenderThrottle.swift` | 4 Markdown Preview, 7 Terminal, 8 HTML Preview | Render coalescing |
| `PreviewImageCache.swift` | 4 Markdown Preview, 8 HTML Preview | Image caching with downsample |
| `ErrorReporting.swift` | 2.7 AI monitors | In-memory log ring buffer |

These are also the four classes in **Category B/C** above — the ones that need the most careful Sendable treatment. Extracting them to a dedicated target forces proper isolation design.

### Design

Create a new SPM target (either as its own top-level directory or inside Foundation's package):

**Option A — New top-level package** (recommended for clarity):

```
SputnikShared/
├── Package.swift
├── Sources/
│   ├── DebounceTimer.swift
│   ├── RenderThrottle.swift
│   ├── PreviewImageCache.swift
│   └── ErrorReporting.swift
├── Tests/
│   └── SputnikSharedTests/
```

Add `SputnikShared` as a dependency of all packages that currently import Foundation for these utilities.

**Option B — New target inside Foundation's `Package.swift`** (smaller diff):

```swift
// 2 Foundation/Package.swift
.target(
    name: "SputnikShared",
    dependencies: []
),
.target(
    name: "FoundationModule",
    dependencies: ["SputnikShared"]
)
```

This keeps the files in the Foundation repo but separates the build target. Either option works — Option A is cleaner (SR-6 at the package level), Option B is a smaller diff.

### What moves

| File | New location | Import changes |
|---|---|---|
| `DebounceTimer.swift` | `SputnikShared/Sources/DebounceTimer.swift` | All callers gain `import SputnikShared` |
| `RenderThrottle.swift` | `SputnikShared/Sources/RenderThrottle.swift` | Same |
| `PreviewImageCache.swift` | `SputnikShared/Sources/PreviewImageCache.swift` | Same |
| `ErrorReporting.swift` | `SputnikShared/Sources/ErrorReporting.swift` | Same |

The `PreviewImageResolver.swift` in module 9 is left in place — it's tightly coupled to ResourcesModule's bundle structure and not a general-purpose utility.

---

## Steps

### Step 1 — Remove `@unchecked` from `@MainActor` classes

1. `SettingsStore.swift`: Remove `@unchecked Sendable`, add doc comment. Build.
2. `WindowState.swift`: Same.
3. `SupportingAIMonitor.swift`: Same.
4. If any build errors appear, add `@MainActor` to the call site or wrap in `Task { @MainActor in }`.

### Step 2 — Add `@MainActor` to `DebounceTimer` and `RenderThrottle`

1. `DebounceTimer.swift`: Add `@MainActor` before `public final class`, remove `@unchecked Sendable`.
2. `RenderThrottle.swift`: Same.
3. Verify all call sites are already `@MainActor` (they are — all usage is in `@MainActor` view models).

### Step 3 — Remove `@unchecked` from actors

1. `ErrorReporting.swift`: Remove `@unchecked Sendable`. If build fails, audit stored properties for non-Sendable types.
2. `PreviewImageCache.swift`: Same.

### Step 4 — Document `@unchecked` on NSFilePresenter subclasses

1. `FileWatcher.swift`: Add doc comment justifying `@unchecked Sendable` (NSFilePresenter requires NSObject).
2. `FileSystemWatcher.swift`: Same.
3. No code change — documentation only.

### Step 5 — Create shared target and move utilities

1. Create `SputnikShared/Package.swift` (Option A) or add target to `2 Foundation/Package.swift` (Option B).
2. Move `DebounceTimer.swift`, `RenderThrottle.swift`, `PreviewImageCache.swift`, `ErrorReporting.swift`.
3. Add `SputnikShared` as a dependency to all packages that import them.
4. Build all targets. Fix any import errors.

### Step 6 — Update Module Guides

In `1 Setup/Module Guides/2 Foundation/2.7 Utilities/guide.md` (or create it if missing):

- Remove `DebounceTimer`, `RenderThrottle`, `PreviewImageCache`, `ErrorReporting` from Foundation's type list
- Note they moved to `SputnikShared`
- Update dependency diagrams

Create `1 Setup/Module Guides/10 SputnikShared/guide.md`:

- Document the four utility types and their purposes
- List which modules depend on SputnikShared

## Risk Assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| Removing `@unchecked` from `@MainActor` classes breaks build | Medium | Each break is a real data-race path. Fix by making the caller `@MainActor`. |
| Actors (`ErrorReporting`, `PreviewImageCache`) have hidden non-Sendable state | Low | Audit stored properties. `ErrorReporting` stores `LogEntry: Sendable`. `PreviewImageCache` stores `[URL: NSImage]` which is actor-isolated. |
| Adding `@MainActor` to `DebounceTimer`/`RenderThrottle` breaks callers | Low | All call sites are already `@MainActor` view models. Build will catch any exceptions. |
| Package restructuring touches many `Package.swift` files | Medium | Option B (new target in existing package) minimises diff. Option A is cleaner but touches 4+ package files. |

## Success Criteria

- [ ] `SettingsStore`, `WindowState`, `SupportingAIMonitor` have no `@unchecked Sendable`
- [ ] `DebounceTimer`, `RenderThrottle` are `@MainActor` with no `@unchecked`
- [ ] `ErrorReporting`, `PreviewImageCache` are plain actors with no `@unchecked`
- [ ] `FileWatcher`, `FileSystemWatcher` have doc comments justifying `@unchecked`
- [ ] `DebounceTimer`, `RenderThrottle`, `PreviewImageCache`, `ErrorReporting` live in a dedicated `SputnikShared` target (not Foundation)
- [ ] All targets build with zero new errors or warnings

## Post-Plan

- [ ] Move this plan to `Plans Completed/` when all steps are done.
- [ ] Update ISS-060 entries to `Resolved` in `References/Issues.md`.
