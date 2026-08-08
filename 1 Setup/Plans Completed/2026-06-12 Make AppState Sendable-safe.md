---
plan: Make `AppState` Sendable-safe (remove `@unchecked`)
status: new
created: 2026-06-11
author: Zed (code analysis)
issue: ISS-052
---

## Summary

`AppState` is declared `@unchecked Sendable`:

```swift
@Observable
@MainActor
public final class AppState: @unchecked Sendable {
```

This annotation suppresses all compiler Sendable checking without providing actual data-race guarantees. It signals "trust me, it's safe" to the compiler without any enforcement. Per **SW-1 (strict actor isolation, no data races)**, all Sendable conformance should be verified by the compiler, not suppressed.

## Root Cause

### Why `@unchecked` was needed

`@Observable` + `@MainActor` classes cannot automatically conform to `Sendable` in current Swift (even with strict concurrency). The stored properties include:

| Property | Type | Sendable? |
|---|---|---|
| `orderedWindowIDs` | `[UUID]` | ✅ `UUID` is `Sendable` |
| `windows` | `[UUID: WindowState]` | ❌ `WindowState` is a `@MainActor` class — not `Sendable` |
| `activeWindowID` | `UUID?` | ✅ |
| `pendingWindowIDs` | `[UUID]` | ✅ |
| `editorCommandHandler` | `EditorCommandHandling?` (protocol) | ❌ Not `Sendable`-constrained |
| `router` | `(any InterPanelRouter)?` (protocol) | ❌ Not `Sendable`-constrained |
| `supportingAIUsage` | `SupportingAIUsage?` | ✅ `Sendable` struct |

The `@unchecked Sendable` exists because `[UUID: WindowState]`, `editorCommandHandler`, and `router` are not Sendable, and the compiler cannot prove that all access goes through `@MainActor` (due to `@Observable`'s generated concurrency interface).

### Safety argument (why `@unchecked` is unnecessary in practice)

`AppState` is **already safe** because:

1. **`@MainActor`** — the class is fully main-actor-isolated. All stored properties are read/written only on the main thread.
2. **`@Observable`** — the macro generates `@MainActor`-isolated accessors. Any off-actor access attempt produces a compiler error on the call site (not a runtime risk).
3. **No escaping Sendable closures** — the class never passes `self` into a detached `Task` or `DispatchQueue` that would require actual `Sendable` conformance.

The `@unchecked` annotation is cargo-cult safety — it was added to silence a warning without investigating why the warning exists.

## Design

### Goal

Replace `@unchecked Sendable` with a verified-safe approach that:

1. **Removes `@unchecked`** — the compiler should enforce safety.
2. **Keeps existing behaviour** — no functional changes.
3. **Documents the safety reasoning** — so future maintainers understand why no `Sendable` conformance is needed.

### Approach: Remove the conformance entirely

Since `AppState` is `@MainActor`, it **does not need** `Sendable` conformance for correct usage. All callers that access `AppState` do so from `@MainActor` context (the SwiftUI view hierarchy, menu commands, `@MainActor` view models). The only reason to require `Sendable` is if `self` is captured in a non-`@MainActor` closure or `Task.detached` — neither of which `AppState` does.

```swift
// Before:
@Observable
@MainActor
public final class AppState: @unchecked Sendable {

// After:
@Observable
@MainActor
public final class AppState {
```

If removing `@unchecked Sendable` causes compile errors, each error reveals a real data-race risk that should be fixed at the call site (e.g., by adding `@MainActor` to the caller or using `Task { @MainActor in … }`).

### Additional audit: `WindowState`, `SettingsStore`, `DocumentSession`

The same pattern exists in other `@Observable @MainActor` classes in the codebase. If the plan succeeds for `AppState`, the same change should be applied to:

| File | Current declaration |
|---|---|
| `2 Foundation/2.3 Settings/SettingsStore.swift:12` | `public final class SettingsStore: @unchecked Sendable` |
| `2 Foundation/2.2 Global State Management/WindowState.swift` | (check — likely same) |
| `2 Foundation/2.2 Global State Management/DocumentSession.swift` | (check — likely same) |

These are scoped as **follow-up** — not part of this plan. The plan only touches `AppState`.

## Steps

### Step 1 — Remove `@unchecked Sendable`

1. In `AppState.swift` line 16, change:
   ```swift
   public final class AppState: @unchecked Sendable {
   ```
   to:
   ```swift
   public final class AppState {
   ```

### Step 2 — Build and fix any compile errors

1. Run `swift build --target FoundationModule`.
2. If the build succeeds:
   - Add a documentation comment above the class declaration explaining why no `Sendable` conformance is needed (Step 3).
3. If the build fails:
   - Each error identifies a call site that crosses an isolation boundary.
   - Fix each one by either:
     a. Adding `@MainActor` to the caller, or
     b. Wrapping the access in `Task { @MainActor in … }`, or
     c. Adding `nonisolated` to the specific method if it truly does not access actor state.
   - **Do not** re-add `@unchecked Sendable` unless the fix requires changing the class's architecture.

### Step 3 — Document the safety reasoning

Update the class doc comment (lines 4–13):

```swift
/// Coordinator for all open windows. Owns the collection of `WindowState` instances
/// and provides computed pass-through accessors that delegate to the active window,
/// so existing callers written against the single-window model continue to compile.
///
/// **Multi-window model:**
/// - One `WindowState` per open window. Created via `createWindow()`.
/// - `activeWindowID` tracks the frontmost window, updated via `setActiveWindow(_:)`.
/// - All "current document / layout" reads delegate to `activeWindow`.
///
/// **Threading:** `@MainActor` — all reads and writes happen on the main thread.
///
/// **Sendable:** This class does not conform to `Sendable`. It is `@MainActor`-isolated,
/// so all property access is confined to the main actor. Callers that need to read
/// `AppState` from outside the main actor must use `Task { @MainActor in … }` or
/// explicitly isolate themselves. Do **not** add `@unchecked Sendable` — it would
/// suppress data-race detection without providing any safety benefit.
```

### Step 4 — Verify with strict concurrency

1. Enable strict concurrency checking for the Foundation target in `Package.swift`:
   ```swift
   .target(
       name: "FoundationModule",
       swiftSettings: [.enableExperimentalFeature("StrictConcurrency")] // or leave as-is if already enabled
   )
   ```
   (Only if not already enabled — check first.)
2. Rebuild. Zero new warnings or errors.
3. If adding strict concurrency causes too many unrelated errors, skip this step and leave a note in the plan.

### Step 5 — Update the Module Guide

In `1 Setup/Module Guides/2 Foundation/2.2 Global State Management/guide.md`:

- Update the **Technical Summary → Threading model** section to mention that `AppState` has no explicit `Sendable` conformance and that `@MainActor` isolation is the safety mechanism.
- Remove any reference to `@unchecked Sendable`.

## Risk Assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| Removing `@unchecked` breaks the build | Medium | Each broken call site reveals a real or potential data-race path. Fix per Step 2. If the fixes cascade, stop and reassess. |
| A Swift update makes `@Observable` + `@MainActor` classes require explicit `Sendable` | Low | This would be a Swift evolution change affecting all `@Observable` classes — would be handled project-wide, not just for `AppState`. |
| Follow-up classes (`SettingsStore`, `WindowState`) need the same treatment | Medium | Scoped as out-of-plan. Create a new plan if needed. |
| `EditorCommandHandling` protocol needs `Sendable` constraint | Low | It's a weak reference (`public weak var router`) and `editorCommandHandler` is set once on `@MainActor`. Neither needs `Sendable`. |

## Success Criteria

- `AppState` has no `@unchecked Sendable` annotation.
- The project builds with zero new errors or warnings.
- A doc comment explains why `Sendable` conformance is absent.
- The Module Guide reflects the change.

## Post-Plan

- [ ] Move this plan to `Plans Completed/` when all steps are done.
- [ ] Update ISS-052 status to `Resolved` in `References/Issues.md`.
- [ ] Optionally: create follow-up plans for `SettingsStore`, `WindowState`, `DocumentSession` if they share the same pattern.
