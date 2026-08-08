---
plan: Extract `loadAll()` from `SettingsStore.swift`
status: new
created: 2026-06-11
author: Zed (code analysis)
issue: ISS-051
---

## Summary

`SettingsStore.loadAll()` (lines 377–501) is a ~125-line method containing ~35 repetitive `if let saved: … = persistence.loadSetting(forKey: …)` blocks. It mixes the settings model (`SettingsStore`) with deserialisation orchestration, violating **SR-6 (one responsibility per file)**.

The loading logic belongs in or alongside `PersistenceService` (module 2.5), where it can be tested independently from `SettingsStore`.

## Current State

`SettingsStore.swift` (502 lines) contains:

| Concern | Lines | Responsibility |
|---|---|---|
| `@Observable` property declarations | 14–170 | State model |
| Computed resolvers + setters | 170–376 | State mutation + persistence write |
| `loadFromDefaults()` | 377–501 | Persistence read + deserialisation |

The private method `loadFromDefaults()` is called from `SettingsStore`'s initialiser. It loops through every `UserDefaults` key, decodes the value, and assigns it to the matching stored property.

## Design

### Goal

Extract the deserialisation orchestration into a separate type without changing the observable property declarations in `SettingsStore` or altering the persistence write path (the existing per-property setters that call `persistence.saveSetting`).

### New type: `SettingsLoader`

A new file `2 Foundation/2.5 Persistence/SettingsLoader.swift` will contain:

```swift
/// Deserialises all `SettingsStore` values from `PersistenceService`.
///
/// Owned by module 2.5 (Persistence) because this is a persistence concern.
/// SettingsStore calls it once on init and then uses per-property setters
/// for all subsequent reads/writes (SR-6).
struct SettingsLoader {
    private let persistence: PersistenceService

    init(persistence: PersistenceService) {
        self.persistence = persistence
    }

    /// Reads every known key from `UserDefaults` and applies the decoded
    /// values to `store`. Falls back to defaults when a key is absent or corrupt.
    func load(into store: SettingsStore) { … }
}
```

### What stays in `SettingsStore.swift`

- All property declarations (`@Observable` stored properties + computed resolvers) — **unchanged**.
- All per-property setters (`setTheme`, `setSpellCheckEnabled`, etc.) — **unchanged**.
- The `private let persistence: PersistenceService` field — stays, it's also used by the per-property setters.

### What moves

- The entire `loadFromDefaults()` method body moves into `SettingsLoader.load(into:)`.

### `SettingsStore` init change

```swift
// Before (pseudocode):
init(persistence: PersistenceService) {
    self.persistence = persistence
    loadFromDefaults()
}

// After:
init(persistence: PersistenceService) {
    self.persistence = persistence
    let loader = SettingsLoader(persistence: persistence)
    loader.load(into: self)
}
```

## Steps

### Step 1 — Create `SettingsLoader`

1. Create `2 Foundation/2.5 Persistence/SettingsLoader.swift`.
2. Define `struct SettingsLoader` with a `persistence: PersistenceService` field.
3. Implement `func load(into store: SettingsStore)`:
   - Copy the full `loadFromDefaults()` method body verbatim.
   - Replace every `self.` assignment with `store.`.
   - The writing-assist legacy migration logic (lines 396–410) moves identically.
   - The AI config legacy migration (lines 494–500) moves identically.

### Step 2 — Replace `loadFromDefaults()` in `SettingsStore`

1. In `SettingsStore.swift`, replace the `loadFromDefaults()` method body with a single call:
   ```swift
   private func loadFromDefaults() {
       let loader = SettingsLoader(persistence: persistence)
       loader.load(into: self)
   }
   ```
2. Verify the method stays `private` — no external callers need it.

### Step 3 — Update the Module Guide

Update `1 Setup/Module Guides/2 Foundation/2.3 Settings/guide.md`:

- Add a line to the **Dependencies** section noting that `SettingsStore` delegates initial load to `SettingsLoader` (2.5).
- No change to the ASCII diagram — the data flow is identical, only the internal routing changes.

Add `1 Setup/Module Guides/2 Foundation/2.5 Persistence/guide.md`:

- If no guide exists for 2.5, create one that documents `PersistenceService` and `SettingsLoader`.
- If a guide exists, add `SettingsLoader` to the key types list.

### Step 4 — Verify

1. Confirm `SettingsStore.swift` line count drops by ~125 lines (502 → ~377).
2. Confirm `SettingsLoader.swift` is ~125 lines.
3. Build: `swift build --target FoundationModule` passes.
4. The writing-assist legacy migration (lines 396–410) and AI config legacy migration (lines 494–500) produce identical results — manual review of the moved code confirms no logic change.

## Risk Assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| `SettingsLoader` accidentally kept `internal` when `SettingsStore` is in a different module | Low | Both are in Foundation module; no cross-module visibility change. |
| Legacy migration ordering changes | Low | Code is copied verbatim, only `self.` → `store.` changes. |
| `SettingsStore` property becomes `private(set)` at some point, breaking `store.` access | Low | `SettingsLoader` would remain in the same module, so `internal` access suffices. |

## Post-Plan

- [ ] Move this plan to `Plans Completed/` when all steps are done.
- [ ] Update ISS-051 status to `Resolved` in `References/Issues.md`.
