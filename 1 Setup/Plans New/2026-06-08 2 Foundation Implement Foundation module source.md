---
plan: Implement Foundation module source
module: 2 Foundation
created: 2026-06-08
status: pending
related_issues: ISS-001
---

## Purpose
Write the Swift source for the entire Foundation module (sub-modules 2.1–2.7) — the shared interface layer, global state, settings, UI primitives, persistence, app lifecycle, and utilities that every other module depends on — so the rest of the build order has a stable, rule-compliant base to build against.

> **Scope note (per user decision):** This plan only *authors `.swift` files* into the existing `2 Foundation/` folders. It does **not** create an Xcode project, `Package.swift`, or any build system, and it does **not** wire up a compile target. Compilation/verification is therefore deferred until a target exists (out of scope here). Every file is written to be Swift 6 strict-concurrency-clean *by inspection*.

> **Foundation flag (skill Rule):** This plan touches module 2 — Foundation. Per the !GenerateAPlan rules, changes here affect *every* other module. Public type names and protocol signatures defined by this plan become the contract all later modules consume; renaming them later is a breaking change.

## Success Condition
All of the following are true by inspection (no build step in scope):

1. Every "Key type" named in guides 2.1–2.7 exists as a Swift file in the matching `2 Foundation/2.x …/` folder.
2. **SR-6** is honoured — one responsibility per file; types are grouped only when they share a resource lifecycle (e.g. `FileType` + its URL classifier).
3. Shared cross-module types are defined **exactly once**: `FileType` (used by 2.1 + 2.2) lives in 2.1; `FocusMode` (defined by 2.4, stored by 2.2) lives in 2.4.
4. **ISS-001 resolved**: there is one `PanelLayout` (slot assignments + sizes) and one `LayoutState` (top-level persisted blob that *contains* a `PanelLayout`) — no duplicate/divergent type.
5. **No force-unwraps** (`!`) in any authored file (SR-2). All optionals handled with `guard let`/`if let`/`Result`/`throws`.
6. **No `DispatchQueue` for business logic, no completion handlers** (SW-1). UI-facing classes are `@MainActor`; cross-`Task` value types are `Sendable`.
7. Foundation stays an **interface layer** (SR-1): cross-module triggers go through protocols (`InterPanelRouter`, `PersistenceService`, `TerminalLifecycle`) — Foundation holds no module-2-external implementation.
8. Every type/method carries `///` DocC doc-comments per **SW-4**.

## Steps

- [ ] 1. **Author the dependency-free value types (2.1, 2.3, 2.4)**
   What: Create the leaf enums/structs that nothing else depends on yet, each in its own file:
   `2.1/FileType.swift` (enum `.text/.markdown/.html/.pdf/.ascii/.binary/.unknown` + an `init(url:)` extension that classifies by extension — grouped per SR-6 same-resource rule),
   `2.3/AppTheme.swift` (`.light/.dark/.system`), `2.3/EditorFont.swift` (`Sendable` struct wrapping font name + point size),
   `2.4/PanelID.swift` (`.fileTree/.textEditor/.markdownPreview/.htmlPreview/.pdfViewer` — Terminal deliberately excluded), `2.4/PanelPosition.swift` (`.left/.centerUpper/.centerLower/.right`), `2.4/FocusMode.swift` (`.dev/.writer/.reader`), `2.4/SputnikAlert.swift` (typed error enum with `title`/`message`).
   Why: These are the shared vocabulary the rest of Foundation references; writing them first means every later file compiles against a real type, not a stub. Defining `FileType` and `FocusMode` once here satisfies SR-1 (single definition) and prevents the kind of duplication that produced ISS-001.

- [ ] 2. **Author the design tokens (2.4)**
   What: `2.4/DesignTokens.swift` housing the pure-constant namespaces `SputnikSpacing` and `SputnikFont` (closely related, grouped per SR-6), plus a separate `2.4/SputnikColor.swift` because it carries light/dark resolution logic (a distinct concern → its own file). `SputnikColor` bridges SwiftUI `Color` and AppKit `NSColor` and resolves via the `colorScheme` environment value (no manual refresh).
   Why: 2.4 is the single home of shared visual primitives (SR-1); all other modules consume these. Separating the logic-bearing colour type from the constant namespaces respects SR-6.

- [ ] 3. **Author `PanelLayout` and resolve ISS-001 (2.4 + 2.5)**
   What: `2.4/PanelLayout.swift` — a `Codable, Sendable` struct with `assignments: [PanelPosition: PanelID]` and `sizes: [PanelPosition: CGFloat]`. Then `2.5/LayoutState.swift` — the top-level `Codable, Sendable` struct serialised to `layout.json`, which *contains* a `PanelLayout` plus `visibility`/`focusMode` and `lastOpenFile: URL?`. Add a doc-comment in both files noting `LayoutState` is the persisted root and `PanelLayout` is its panel-arrangement component.
   Why: This directly resolves ISS-001 — the two guide names become one coherent containment relationship (`LayoutState` ⊃ `PanelLayout`) instead of two divergent types, honouring SR-1.

- [ ] 4. **Author the Persistence layer (2.5)**
   What: `2.5/PersistenceService.swift` — a `@MainActor` protocol (`restore()`, `flushLayout()`, `writeRecovery(for:content:)`, settings read/write) registered in Foundation. `2.5/FilePersistenceService.swift` — the concrete `@MainActor` class: `UserDefaults` for lightweight settings; `~/Library/Application Support/Sputnik/` (resolved once via `FileManager.urls(...)`) for `layout.json` + `recovery/`. Recovery/layout disk writes dispatched with `Task(priority: .utility)`; all I/O wrapped in `do/catch` returning `Result`/`throws` (SR-2). Replace `.gitkeep` in this folder.
   Why: Single durable-data entry point (guide 2.5) so no other module touches storage directly (SR-1). `.utility` QoS keeps writes off the UI path (SR-4/MR-3); explicit error handling satisfies SR-2.

- [ ] 5. **Author the Settings store (2.3)**
   What: `2.3/SettingsStore.swift` — `@Observable @MainActor` class owning `theme/editorFont/autoSaveEnabled/lineNumbersEnabled/wordWrapEnabled/spellCheckEnabled/grammarCheckEnabled`. Reads defaults via `PersistenceService` (protocol, injected), falls back to hardcoded defaults when `UserDefaults` is nil or a `Codable` decode fails (no crash). Persists changes through `PersistenceService` on a `.utility` Task.
   Why: Guide 2.3 — one observable preferences store every module reads from; depending on the `PersistenceService` *protocol* (not the concrete service) keeps Foundation an interface layer (SR-1).

- [ ] 6. **Author Global State (2.2)**
   What: `2.2/AppState.swift` — `@Observable @MainActor` class owning `activeWorkspaceDirectory: URL?`, `currentlyOpenFile: URL?`, `currentlyOpenFileType: FileType`, and `focusMode: FocusMode`. Document that the only writer is `InterPanelRouter` (2.1) and all other modules are read-only `@Environment` consumers; background file-system events must hop to `@MainActor` before mutating.
   Why: Guide 2.2 — single thread-safe source of truth. `@MainActor` isolation makes the "main-thread-only writes" rule a compile-time guarantee (SW-1, SR-4).

- [ ] 7. **Author the Inter-panel routing contract (2.1)**
   What: `2.1/PanelEvent.swift` — `Sendable` enum (`fileOpened(URL, FileType)`, `directoryChanged(URL)`). `2.1/InterPanelRouter.swift` — `@MainActor` protocol declaring `open(_ file: URL)` and `syncDirectory(_ url: URL)`, plus an `AsyncStream<PanelEvent>` accessor for observers. Protocol only — **no concrete router implementation** (guide 2.1: "registered in Foundation, never implemented here").
   Why: SR-1 — Foundation exposes the routing *protocol* and event vocabulary; the concrete glue is wired up where the app is assembled, not inside Foundation. `AsyncStream` (not callbacks) satisfies SW-1.

- [ ] 8. **Author the Terminal-lifecycle seam (2.6 support)**
   What: `2.6/TerminalLifecycle.swift` — a `@MainActor` protocol with `killAllPTYs() async` that module 7 will implement later. `AppDelegate` will hold a `weak` optional reference to it.
   Why: Guide 2.6 has `AppDelegate` calling `TerminalManager.killAllPTYs()`, but `TerminalManager` is module 7 and out of scope. A Foundation-owned protocol lets the lifecycle code compile and stay decoupled (SR-1) without reaching into module 7 internals.

- [ ] 9. **Author the Utilities (2.7)**
   What: `2.7/DebounceTimer.swift` — wraps a single cancellable `Task` using `Task.sleep`; `schedule(delay:work:)` cancels any pending task and starts a fresh one; `cancel()` discards pending work; `CancellationError` swallowed internally. No `DispatchQueue`.
   Why: Guide 2.7 — shared debounce utility for later ghost-text consumers (module 3). Pure Swift Concurrency keeps it composable (SW-1) and dependency-free.

- [ ] 10. **Author the App lifecycle + root view (2.6)**
   What: `2.6/AppDelegate.swift` — `@MainActor NSObject, NSApplicationDelegate`: `applicationDidFinishLaunching` → `PersistenceService.restore()` (+ crash-recovery dialog hook); `applicationShouldTerminate` → `TerminalLifecycle.killAllPTYs()` returning `.terminateLater` then `replyToApplicationShouldTerminate(true)`; `applicationWillTerminate` → `PersistenceService.flushLayout()`; `weak var mainWindow: NSWindow?`. `2.6/ContentView.swift` — root SwiftUI layout that *reserves* the named slots (`.left/.centerUpper/.centerLower/.right` + pinned Terminal area) with placeholder views, since the real panels are other modules. `2.6/SputnikApp.swift` — `@main struct SputnikApp: App` with `@NSApplicationDelegateAdaptor`, a `WindowGroup` using `.handlesExternalEvents` for single-window enforcement, the `Settings` scene, and `.environment(...)` injection of `AppState` + `SettingsStore`.
   Why: Guide 2.6 (Option B hybrid) — this is the single entry point wiring Foundation together. Building it last means every dependency it injects/calls already exists. `weak` window ref + `[weak self]` in any escaping closures satisfy SW-2.

- [ ] 11. **Cross-file consistency + rules audit**
   What: Re-read all authored files together. Verify: shared types defined once (Success Condition 3); `LayoutState`/`PanelLayout` containment is the only layout representation (SC 4 / ISS-001); zero `!` force-unwraps (SC 5); no `DispatchQueue`/completion handlers, `@MainActor` on UI classes, `Sendable` on cross-`Task` types (SC 6); every type has a `///` doc-comment (SW-4). Fix any drift found.
   Why: SR-1/SR-6 violations between files only become visible when the set is read as a whole; this pass is the in-scope substitute for a compiler (no build target exists yet).

## Risks and Constraints
- **No build verification (user-chosen scope).** Without an Xcode target nothing is compiled; correctness rests on the Step 11 inspection pass. A later "create app target" plan is the natural follow-up before this code can actually run.
- **Foundation is the shared contract (skill Rule).** Type names/protocol signatures set here ripple to all later modules — treat them as a public API; renames later are breaking.
- **SR-1 must not erode.** Tempting shortcuts (a concrete router, AppDelegate calling module 7 directly) are explicitly avoided via protocols (`InterPanelRouter`, `TerminalLifecycle`). Keep Foundation an interface layer, not an orchestrator.
- **SW-1 strict concurrency.** Anything crossing a `Task` boundary must be `Sendable`; all UI types `@MainActor`. Written for Swift 6 mode so it won't need rework when a target is added.
- **ISS-001** is resolved *in this plan* by the `LayoutState ⊃ PanelLayout` design (Step 3). On approval + completion its status moves to Resolved.
- **Module-guide naming follow-up:** guides 2.4 and 2.5 should later be reconciled to the containment naming; the guide edits are part of closeout, not a separate plan.

## Files Affected
- `2 Foundation/2.1 Inter-Panel communication/FileType.swift` — `FileType` enum + URL classifier (shared with 2.2)
- `2 Foundation/2.1 Inter-Panel communication/PanelEvent.swift` — `Sendable` event enum broadcast to observers
- `2 Foundation/2.1 Inter-Panel communication/InterPanelRouter.swift` — `@MainActor` routing **protocol** (no implementation)
- `2 Foundation/2.2 Global State Management/AppState.swift` — `@Observable @MainActor` single source of truth
- `2 Foundation/2.3 Settings/AppTheme.swift` — theme enum
- `2 Foundation/2.3 Settings/EditorFont.swift` — `Sendable` font struct
- `2 Foundation/2.3 Settings/SettingsStore.swift` — `@Observable @MainActor` preferences store
- `2 Foundation/2.4 UI and UX/DesignTokens.swift` — `SputnikSpacing` + `SputnikFont` constant namespaces
- `2 Foundation/2.4 UI and UX/SputnikColor.swift` — SwiftUI/AppKit colour bridge with light/dark resolution
- `2 Foundation/2.4 UI and UX/PanelID.swift` — relocatable-panel identifiers (Terminal excluded)
- `2 Foundation/2.4 UI and UX/PanelPosition.swift` — named slot enum
- `2 Foundation/2.4 UI and UX/PanelLayout.swift` — `Codable` slot assignments + sizes (component of `LayoutState`)
- `2 Foundation/2.4 UI and UX/FocusMode.swift` — focus-mode enum (stored in `AppState`)
- `2 Foundation/2.4 UI and UX/SputnikAlert.swift` — typed error enum for all dialogs
- `2 Foundation/2.5 Persistence/LayoutState.swift` — top-level persisted `Codable` blob (contains `PanelLayout`) — **resolves ISS-001**
- `2 Foundation/2.5 Persistence/PersistenceService.swift` — `@MainActor` persistence **protocol**
- `2 Foundation/2.5 Persistence/FilePersistenceService.swift` — concrete `UserDefaults` + Application Support implementation (replaces `.gitkeep`)
- `2 Foundation/2.6 App Lifecycle/TerminalLifecycle.swift` — `@MainActor` PTY-cleanup **protocol** (module 7 implements later)
- `2 Foundation/2.6 App Lifecycle/AppDelegate.swift` — `NSApplicationDelegate` (launch / terminate gate / flush)
- `2 Foundation/2.6 App Lifecycle/ContentView.swift` — root layout reserving the named slots (placeholder panels)
- `2 Foundation/2.6 App Lifecycle/SputnikApp.swift` — `@main` entry point, `WindowGroup` + `Settings` scene + env injection
- `2 Foundation/2.7 Utilities/DebounceTimer.swift` — cancellable `Task.sleep`-based debounce
- `1 Setup/References/Issues.md` — ISS-001 status → Resolved (closeout)
- `1 Setup/Module Guides/2 Foundation/2.4 …/guide.md` & `2.5 …/guide.md` — `status`/`last_updated` + naming reconciliation (closeout)

## Closeout
- [ ] Re-read the Purpose statement — does the outcome match it exactly?
- [ ] Success Condition verified (Step 11 inspection pass — all 8 points confirmed)
- [ ] ISS-001 marked Resolved in `Issues.md`
- [ ] Module Guide(s) 2.1–2.7 updated (`status` + `last_updated`); 2.4/2.5 layout naming reconciled
- [ ] Changes committed: `[2 Foundation] Implement Foundation module source`
- [ ] Pushed to GitHub
- [ ] Plan moved to Plans Completed/
