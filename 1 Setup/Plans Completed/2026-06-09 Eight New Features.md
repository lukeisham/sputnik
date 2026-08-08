# Plan: Eight New Features
**Date:** 2026-06-09  
**Status:** Complete
**Modules touched:** 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 3, 4, 7, 8 + new Scratchpad module (10)

---

## Working Conventions

These apply to **every feature in this plan** without exception. They are not reminders — they are preconditions.

### 1. Guide-read-first
Before writing a single line of code for a feature, read every Module Guide listed in its **Module guide changes** section. The guide is the source of truth for that module's design intent. If the guide conflicts with what the code already does, log the discrepancy with `!TrackIssues` before continuing.

### 2. Update guides before and during implementation
Module guide changes are listed at the end of each feature section. These updates must be made **as part of the feature work** — not after. The guide for each module must reflect the new types and state before the implementation PR is considered done.

### 3. Vibe Coding Rules compliance checklist
Every feature must be verified against these rules before the commit. Check each one explicitly:

| Rule | Check |
|---|---|
| **SR-1** | All new shared types and settings defined once in Foundation (2.x); no module reaches into another module's internals; cross-module calls go through Foundation protocols |
| **SR-2** | No force-unwraps (`!`) in non-test code; every guard/if-let/Result/throws path is handled; file I/O and system calls treated as fallible |
| **SR-3** | No file loaded into memory when it can be streamed; new objects lazy-load; background tasks release resources when cancelled |
| **SR-4** | Main thread is UI-only; every system call, polling loop, or heavy computation runs in a `Task(priority:)` or background actor; `@MainActor` annotation on all UI-touching classes |
| **SR-5** | No third-party Swift packages introduced; Apple frameworks used for all new functionality |
| **SR-6** | Each new file has one clearly scoped responsibility; no "utility grab-bag" files |
| **SW-1** | Only `async/await`, `Task`, `AsyncStream` for new async code; no new `DispatchQueue.async` for business logic |
| **SW-2** | `[weak self]` in every escaping closure and every long-lived `Task` that captures `self`; polling loops and stream listeners always use `[weak self]` |
| **SW-3** | New views built in SwiftUI; `NSViewRepresentable` used only where documented performance need exists (Scratchpad's `NSTextView` qualifies — plain-text editing; document the reason) |
| **SW-4** | Public types and functions have `///` DocC comments with `- Parameters:`, `- Returns:`, `- Throws:` where applicable |
| **MR-2** | File watching uses `NSFilePresenter` / `FileManager`; no polling on a timer for file-system state |
| **MR-3** | Background work uses `Task(priority:)` with appropriate QoS; see table in Vibe Rules |

### 4. Issue-first
If anything unexpected is found mid-implementation — a naming conflict, a missing Foundation type, a threading assumption that doesn't hold — log it with `!TrackIssues` before continuing. Do not work around undocumented problems silently.

### 5. Commit and push after each feature
After completing each feature (code done + module guides updated + rules checked):
```
git add <changed files>
git commit -m "[Feature] <F-N description>"
git push
```
Use the exact feature label as the commit prefix (e.g. `[F-1] Sputnik logo and menu-bar status item`).

### 6. Plan completion
After F-8 is committed and pushed:
1. Change the **Status** field at the top of this file from `New` to `Complete`.
2. Move this file from `1 Setup/Plans New/` to `1 Setup/Plans Completed/`.
3. Commit and push: `[Plan] Mark Eight New Features plan complete`.

---

## Overview

| # | Feature | Primary module(s) |
|---|---|---|
| F-1 | Sputnik logo — app icon + menu-bar status item | App bundle, 2.4, 2.6 |
| F-2 | About window | 2.4, 2.6 |
| F-3 | AI agent credentials in Settings | 2.3, 2.7 |
| F-4 | Per-panel fonts and background colours | 2.3, 3, 4, 8 |
| F-5 | Bottom status bar | 2.2, 2.3, 2.4, 2.7 |
| F-6 | Scratchpad panel | 2.2, 2.4, 2.5, new module 10 |
| F-7 | Universal slash-command auto-complete | 2.4, 2.7, 3, 10 |
| F-8 | Terminal model detection → status bar | 2.2, 2.4, 2.7, 7 |

**Known issues logged as part of this plan:** ISS-012, ISS-013, ISS-014 (see References/Issues.md).

**Safe parallel build order:**
```
F-1 (logo assets)
  └─▶ F-2 (About window — needs SputnikLogo asset)
F-3 (AI settings + KeychainService)
  └─▶ F-5 (status bar — needs aiConfig.modelName)
        └─▶ F-8 (terminal model detection — extends StatusBarView)
F-4 (per-panel fonts/colours — isolated SettingsStore change)
F-6 (Scratchpad — needs AppState + PersistenceService only)
  └─▶ F-7 (slash commands — needs Scratchpad + Text Editor as consumers)
```
F-1, F-3, F-4, F-6 can be developed in parallel. F-2 waits on F-1. F-5 waits on F-3. F-7 waits on F-6. F-8 waits on F-5.

---

## F-1 — Sputnik Logo (app icon + menu-bar status item)

### What
- **App icon** — full-resolution Sputnik satellite icon at all required macOS sizes (16 → 1024 pt) in `App-Sputnik/Assets.xcassets/AppIcon.appiconset`.
- **Menu-bar status item** — an `NSStatusItem` with a small monochrome Sputnik template image (16×16 @1x, 32×32 @2x) in the macOS menu bar while Sputnik is running.

### Design
The logo is a stylised Sputnik satellite (sphere + four angled antennae). App icon: sphere carries the letter S. Menu-bar template image: pure monochrome so macOS tints it correctly in light/dark modes.

### Assets needed
```
App-Sputnik/Assets.xcassets/
  AppIcon.appiconset/          ← 10 PNG sizes (16,32,64,128,256,512 pt @1x and @2x)
  SputnikMenuBar.imageset/     ← 16pt @1x + 32pt @2x template PNGs
  SputnikLogo.imageset/        ← 64pt @1x + 128pt @2x full-colour for About window
```

### Implementation
1. **Asset creation** — produce the three imagesets above. `SputnikMenuBar` images must have `isTemplate = true` set in the asset catalogue so AppKit tints them automatically.
2. **`SputnikMenuBarController`** (new file, `2 Foundation/2.6 App Lifecycle/SputnikMenuBarController.swift`) — `@MainActor` class; creates and holds the `NSStatusItem` on app launch. Observes `AppState.isProcessing`; when `true`, applies a `CABasicAnimation` rotation to the status-item button's `CALayer`. The spin is driven by the same `AppState.isProcessing` flag as the status bar (F-5) — single source of truth (SR-1).
3. **Wiring in `AppDelegate`** — `applicationDidFinishLaunching` instantiates `SputnikMenuBarController` and holds it as a `strong` property (never deallocated for app lifetime).

### Vibe Coding Rules check
- **SR-1** `SputnikMenuBarController` lives in Foundation (2.6), not in a panel module.
- **SR-2** `NSStatusItem` creation can return nil on older OS — guard against it.
- **SR-4** `CABasicAnimation` runs on `CALayer` (render thread); `isProcessing` observation is `@MainActor`.
- **SW-2** `AppState` is observed via `withObservationTracking`; use `[weak self]` in the change handler.
- **SW-3** `NSStatusItem` is AppKit-only — no SwiftUI equivalent exists; use is justified and documented.
- **SW-4** Add `///` comments to `SputnikMenuBarController` public interface.

### Module guide changes
- **2.6 App Lifecycle** — add `SputnikMenuBarController` to the lifecycle diagram and technical summary.
- **2.4 UI/UX** — add `SputnikMenuBar` and `SputnikLogo` as named design-token image assets.

### Commit
`[F-1] Sputnik logo — app icon assets and menu-bar status item`

---

## F-2 — About Window

### What
A custom macOS About panel showing:
- `SputnikLogo` image (128 pt).
- App name, version (from `CoreSputnik`), build number.
- Credits block: Purpose, Credits, GitHub link (drawn from README — hard-coded string, not loaded at runtime).
- Opened via **App ▸ About Sputnik**.

### Design
```
┌────────────────────────────────────┐
│         [SputnikLogo 128pt]        │
│                                    │
│              Sputnik               │
│           Version 1.0 (1)          │
│                                    │
│  A native macOS development        │
│  environment …                     │
│                                    │
│  Credits: Keith Foster · Nate Jones│
│  github.com/lukeisham/sputnik      │
│                                    │
│              [ OK ]                │
└────────────────────────────────────┘
```

### Implementation
1. **`AboutWindowView`** (new file, `2 Foundation/2.4 UI and UX/AboutWindowView.swift`) — SwiftUI `View`; logo + title + version string + credits text. Credits are a static `let` string — not loaded from disk at runtime (SR-3, SR-5).
2. **`Window("About Sputnik", id: "about")` scene** in `SputnikApp.body` — fixed size, no resize handle, no toolbar.
3. **Menu wiring** — add `AboutSputnik` command to `SputnikCommands` (2.0); calls `openWindow(id: "about")`.
4. **Single-instance guard** — `.handlesExternalEvents(matching: [])` on the scene; second activation brings the existing window front, not a duplicate.

### Vibe Coding Rules check
- **SR-1** `AboutWindowView` lives in Foundation (2.4); version string sourced from `CoreSputnik` (existing package).
- **SR-2** `openWindow` is a safe SwiftUI call; no force-unwraps.
- **SR-5** SwiftUI `Window` scene — native framework.
- **SW-3** Pure SwiftUI; no AppKit needed.
- **SW-4** `///` comment on `AboutWindowView`.

### Module guide changes
- **2.6 App Lifecycle** — add `Window("about")` to the `SputnikApp` scene diagram.
- **2.4 UI/UX** — add `AboutWindowView` to key types.

### Commit
`[F-2] About window with logo, version, and credits`

---

## F-3 — AI Agent Credentials in Settings

### What
A new **AI** tab in the macOS Settings window:
- Model name/ID (e.g. `claude-sonnet-4-6`).
- API key — stored in the macOS **Keychain only**, never `UserDefaults`.
- Optional base URL (for proxies or self-hosted endpoints).

The model name is consumed by the status bar (F-5) and any future AI-calling feature.

### Design
```
  Settings  [Appearance]  [Editor]  [Grammar]  [Terminal]  [AI]
  ┌──────────────────────────────────────────────────────┐
  │  AI                                                  │
  │                                                      │
  │  Model     [claude-sonnet-4-6              ]         │
  │  API Key   [••••••••••••••••••   Show / Clear]       │
  │  Base URL  [https://api.anthropic.com      ]  Clear  │
  │                                                      │
  │  ⚠ API key is stored in macOS Keychain.             │
  └──────────────────────────────────────────────────────┘
```

### New types
- **`AIConfiguration`** (`Sendable`, `Codable`) — `modelName: String`, `baseURL: URL?` only; no API key field. Lives in `2 Foundation/2.3 Settings/AIConfiguration.swift`.
- **`ModelCapacity`** (enum, `2 Foundation/2.3 Settings/ModelCapacity.swift`) — static `contextWindow(for modelName: String) -> Int?` lookup. Seeded with current Claude model family; returns nil for unknown models. Shared by F-5 context % and F-8 terminal model detection.
- **`KeychainService`** (`@MainActor`, `2 Foundation/2.7 Utilities/KeychainService.swift`) — thin wrapper around `Security.framework` `SecItem*` C API; `save(key:service:)`, `load(service:) -> String?`, `delete(service:)`; service label `"com.sputnik.aiAPIKey"`. Resolves ISS-014.
- **`SettingsStore.aiConfig: AIConfiguration`** — new stored field; `modelName` + `baseURL` persisted via `PersistenceService`; API key read/written via `KeychainService` at call time, never cached.
- **`AISettingsView`** (new file, `2 Foundation/2.3 Settings/AISettingsView.swift`) — SwiftUI view for the AI tab.

### Vibe Coding Rules check
- **SR-1** All new types in Foundation; `SettingsStore` remains the single settings source.
- **SR-2** `SecItem*` calls return `OSStatus`; every non-`errSecSuccess` path handled; no force-unwrap on the returned `CFTypeRef`.
- **SR-5** `Security.framework` — native Apple framework.
- **SR-6** `KeychainService`, `AIConfiguration`, `ModelCapacity`, `AISettingsView` — four separate files, four separate responsibilities.
- **SW-1** `KeychainService` methods are synchronous (Keychain C API has no async variant — document this at the call site per MR-3).
- **SW-4** `///` comments on `KeychainService` public methods; `- Throws:` noting Keychain error codes.

### Module guide changes
- **2.3 Settings** — add `AIConfiguration`, `ModelCapacity`, `aiConfig` to owned-state list; add AI tab to Settings window diagram.
- **2.7 Utilities** — add `KeychainService` to key types and known consumers table.

### Commit
`[F-3] AI credentials settings tab with Keychain-backed API key storage`

---

## F-4 — Per-Panel Fonts and Background Colours

### What
Text Editor, Markdown Preview, and HTML Preview each get independently configurable font and background colour. Per-panel values override the global `editorFont`; if a per-panel value is nil, global `editorFont` is the fallback. Resolves ISS-012.

### New SettingsStore fields
```swift
// Per-panel font overrides (nil = inherit global editorFont)
var textEditorFont: EditorFont?
var markdownPreviewFont: EditorFont?
var htmlPreviewFont: EditorFont?

// Per-panel background colours
var textEditorBackground: SputnikColor        // default: system background
var markdownPreviewBackground: SputnikColor
var htmlPreviewBackground: SputnikColor
```

### Computed resolvers (on SettingsStore)
```swift
var resolvedTextEditorFont: EditorFont     { textEditorFont     ?? editorFont }
var resolvedMarkdownPreviewFont: EditorFont { markdownPreviewFont ?? editorFont }
var resolvedHtmlPreviewFont: EditorFont    { htmlPreviewFont    ?? editorFont }
```

### Settings UI
Expand the **Appearance** tab with three collapsible sub-sections (Text Editor / Markdown Preview / HTML Preview), each containing a font picker and a colour well.

### Consumer changes
- **Module 3 (Text Editor)** — replace `settingsStore.editorFont` with `resolvedTextEditorFont`; read `textEditorBackground`.
- **Module 4 (Markdown Preview)** — read `resolvedMarkdownPreviewFont` and `markdownPreviewBackground`; inject background as a CSS variable override into `WKWebView`'s injected stylesheet.
- **Module 8 (HTML Preview)** — same pattern as module 4.

### Vibe Coding Rules check
- **SR-1** All new fields on `SettingsStore`; File Tree and Terminal continue to consume `editorFont` unchanged — no duplication.
- **SR-2** `EditorFont?` optionals unpacked via `??` fallback — no force-unwraps.
- **SR-3** Colour wells hold `SputnikColor` value types — no retained view objects.
- **SW-3** Font picker and colour well are SwiftUI `ColorPicker` / `FontPicker` — no AppKit overlay needed.
- **SW-4** `///` on the three computed resolver properties.

### Module guide changes
- **2.3 Settings** — add six new fields and three computed resolvers to owned-state list; update Appearance tab diagram.
- **3 Text Editor / 3.1 Text** — replace `editorFont` reference with `resolvedTextEditorFont`; add `textEditorBackground` note.
- **4 Markdown Preview** — add CSS variable background injection note.
- **8 HTML Preview** — add CSS variable background injection note.

### Commit
`[F-4] Per-panel fonts and background colours for editor, markdown, and HTML views`

---

## F-5 — Bottom Status Bar

### What
A thin strip (24 pt) fixed at the very bottom of the Sputnik window (below Terminal), always visible:

```
[ 🛰  ]  claude-sonnet-4-6   CTX 34%   RAM 48 MB   CPU 2.1%
  ↑ spins when isProcessing    ↑ CTX hidden if no AI model configured
```

**Segments:**
- **Satellite icon** — static when `AppState.isProcessing == false`; SwiftUI `rotationEffect` animation when `true`. Same flag as F-1 menu-bar item — single source of truth.
- **AI model** — `SettingsStore.aiConfig.modelName`; `"—"` if empty.
- **Context % (conditional)** — shown only when `aiConfig.modelName` is non-empty and `AppState.contextUsage` is non-nil. Hidden entirely when no model is configured.
- **RAM** — resident-set size of the Sputnik process, polled every 2 s.
- **CPU %** — CPU usage of the Sputnik process (all threads), polled every 2 s.

Note: F-8 adds a second conditional segment for terminal-detected models; `StatusBarView` must be designed to accommodate it via optional child views.

### New types

**`ContextUsage`** (`Sendable`, `2 Foundation/2.2 Global State Management/ContextUsage.swift`):
```swift
struct ContextUsage: Sendable {
    let usedTokens: Int
    let contextWindow: Int
    var percent: Double { Double(usedTokens) / Double(contextWindow) * 100 }
}
```
Written to `AppState.contextUsage: ContextUsage?` by any module that makes AI calls. Context window size looked up from `ModelCapacity` (introduced in F-3).

**`ProcessMonitor`** (`@Observable @MainActor`, `2 Foundation/2.7 Utilities/ProcessMonitor.swift`):
```swift
@Observable @MainActor
final class ProcessMonitor {
    private(set) var ramMB: Int = 0
    private(set) var cpuPercent: Double = 0.0
    private var pollingTask: Task<Void, Never>?

    func start() { ... }   // begins 2-second Task(priority: .background) polling loop
    func stop()  { ... }   // cancels the task; [weak self] in the loop body
}
```
Samples `mach_task_basic_info` (RAM) and thread CPU time via `thread_basic_info`. Resolves ISS-013.

**`AppState` additions** (resolves ISS-013):
- `private var processingCount: Int = 0`
- `var isProcessing: Bool { processingCount > 0 }`
- `func beginProcessing()` / `func endProcessing()` — increment/decrement counter; concurrent operations don't race.
- `var contextUsage: ContextUsage?`

**`StatusBarView`** (`2 Foundation/2.4 UI and UX/StatusBarView.swift`) — SwiftUI `HStack`; reads `AppState`, `SettingsStore`, and `ProcessMonitor` from environment. Context segment:
```swift
if let usage = appState.contextUsage, !settingsStore.aiConfig.modelName.isEmpty {
    Text("CTX \(Int(usage.percent))%")
}
```

### Layout change
```
ContentView VStack
  ├── DocumentTabBar          (existing)
  ├── main HSplitView         (existing)
  ├── Terminal strip          (existing)
  └── StatusBarView           (new — 24 pt fixed height, non-resizable)
```

### Wiring
- `ProcessMonitor` singleton created at launch alongside `AppState`; injected via `.environment(processMonitor)`.
- `AppDelegate.applicationDidFinishLaunching` → `processMonitor.start()`.
- `AppDelegate.applicationWillTerminate` → `processMonitor.stop()`.

### Vibe Coding Rules check
- **SR-1** `ProcessMonitor`, `ContextUsage`, `AppState` additions all in Foundation; `StatusBarView` in 2.4.
- **SR-2** `mach_task_basic_info` returns a kern return code — check it; don't force-unwrap.
- **SR-4** Polling loop runs `Task(priority: .background)`; marshals to `@MainActor` via `await MainActor.run { }`.
- **SW-1** `Task(priority: .background)` loop with `try? await Task.sleep(...)`.
- **SW-2** `[weak self]` inside the `ProcessMonitor` polling `Task` — it is an infinite loop and would otherwise retain `self` for the app lifetime.
- **SW-3** `StatusBarView` is pure SwiftUI.

### Module guide changes
- **2.2 Global State** — add `processingCount`, `isProcessing`, `beginProcessing()`, `endProcessing()`, `contextUsage`, `ContextUsage` to AppState owned-state list.
- **2.3 Settings** — add `ModelCapacity` context-window lookup to `AIConfiguration` section.
- **2.4 UI/UX** — add `StatusBarView` to key types; update the layout diagram.
- **2.7 Utilities** — add `ProcessMonitor` to key types and known consumers table.
- **2.6 App Lifecycle** — add `ProcessMonitor` start/stop to the lifecycle diagram.

### Commit
`[F-5] Bottom status bar with satellite icon, AI model, context %, RAM and CPU`

---

## F-6 — Scratchpad Panel

### What
A resizable, draggable overlay panel anchored bottom-right of the content area. Contains a single plain-text `NSTextView`. Text persists across launches. Opened/closed via **View ▸ Scratchpad** (⌘⇧K).

### Design
```
┌─────────────────────────────────────────────────────────┐
│ panels …                                                │
│                                       ┌──────────────┐ │
│                                       │  Scratchpad  │ │
│                                       │              │ │
│                                       │  NSTextView  │ │
│                                       └──────────────┘ │
├─────────────────────────────────────────────────────────┤
│ Terminal                                                │
├─────────────────────────────────────────────────────────┤
│ StatusBar                                               │
└─────────────────────────────────────────────────────────┘
```

Default size: 320 × 240 pt. Minimum: 200 × 120 pt. Drag title bar to reposition; resize from any edge. Size and position persisted.

### New state
- **`AppState.scratchpadVisible: Bool`** — toggled by View menu command.
- **`PersistenceService` additions** — `scratchpadText: String` (UserDefaults; acceptable for non-sensitive scratch content), `scratchpadFrame: CGRect`.

### New types
- **`ScratchpadTextView`** (`NSViewRepresentable`, `2 Foundation/2.4 UI and UX/ScratchpadTextView.swift`) — wraps a plain `NSTextView`; no spell-check underlines by default; binds to `@Binding<String>`. `NSViewRepresentable` is justified here: `NSTextView` provides raw plain-text editing performance that `TextEditor` cannot match for an unstructured scratchpad (SW-3 — document this at the call site).
- **`ScratchpadPanel`** (`2 Foundation/2.4 UI and UX/ScratchpadPanel.swift`) — SwiftUI container; title bar ("Scratchpad" + close button), resize handles, drag gesture. Applied as `.overlay(alignment: .bottomTrailing)` in `ContentView`.

### Slash-command note
When F-7 is implemented, `ScratchpadTextView` becomes a consumer of `SlashCommandRegistry` exactly like the Text Editor.

### Vibe Coding Rules check
- **SR-1** `ScratchpadPanel`, `ScratchpadTextView`, `AppState.scratchpadVisible` all in Foundation (2.4 / 2.2).
- **SR-2** `PersistenceService` `CGRect` decode can fail — use default frame on failure; no crash.
- **SR-3** Scratchpad text stored once in `PersistenceService`; `NSTextView` does not hold a separate copy.
- **SW-2** `ScratchpadTextView` coordinator's `NSTextViewDelegate` callbacks use `[weak self]`.
- **SW-3** `NSViewRepresentable` use is documented — plain-text editing performance requirement.

### Module guide changes
- **2.2 Global State** — add `scratchpadVisible` to `AppState` owned-state list.
- **2.4 UI/UX** — add `ScratchpadPanel`, `ScratchpadTextView` to key types; add overlay to layout diagram.
- **2.5 Persistence** — add `scratchpadText` and `scratchpadFrame` to persisted keys table.

### Commit
`[F-6] Scratchpad panel — plain-text overlay with persisted content and position`

---

## F-7 — Universal Slash-Command Auto-Complete

### What
Typing `/` at a word boundary in any Sputnik text input (Text Editor and Scratchpad) triggers a floating command palette. The user types to filter; ↩ or click inserts the command's template text and dismisses the popup.

### Design
```
  | /head|
    ┌──────────────────────┐
    │ /heading1   H1 block │
    │ /heading2   H2 block │
    │ /heading3   H3 block │
    └──────────────────────┘
```
Popup is anchored to the cursor; dismissed by Escape, focus loss, or confirmed selection.

### New types in 2.7 Utilities

**`SlashCommand`** (`Sendable`, `2 Foundation/2.7 Utilities/SlashCommand.swift`):
```swift
struct SlashCommand: Sendable, Identifiable {
    let id: String        // e.g. "markdown.heading1"
    let label: String     // shown in list
    let detail: String    // short description
    let category: String  // popup section header
    let insert: String    // text substituted at trigger point
}
```

**`SlashCommandRegistry`** (`@Observable @MainActor`, `2 Foundation/2.7 Utilities/SlashCommandRegistry.swift`) — `register(_ commands: [SlashCommand])` called by each module at launch; `matches(for prefix: String) -> [SlashCommand]` for case-insensitive prefix filtering.

### New type in 2.4 UI/UX

**`SlashCommandPopup`** (`2 Foundation/2.4 UI and UX/SlashCommandPopup.swift`) — SwiftUI `View`; filtered `List` of `SlashCommand` rows; `onSelect: (SlashCommand) -> Void` callback. Host controls visibility via `@State var slashPopupCommands: [SlashCommand]`.

### Integration pattern (Text Editor and Scratchpad)

Each `NSTextView` subclass:
1. `textView(_:shouldChangeTextIn:replacementString:)` — `/` at word boundary → set `slashPopupCommands = registry.matches(for: "")`.
2. Subsequent keystrokes while popup is open → `registry.matches(for: currentToken)`.
3. `onSelect(command)` → replace `/…` range with `command.insert`; dismiss popup.
4. Escape / focus loss → dismiss; leave typed text unchanged.

### Command sets registered at launch

| Module | Category | Example commands |
|---|---|---|
| 3.2 Markdown | Markdown | `/h1` `/h2` `/h3` `/bold` `/italic` `/code` `/codeblock` `/table` `/link` `/image` `/hr` |
| 3.4 HTML | HTML | `/div` `/span` `/section` `/article` `/p` `/ul` `/ol` `/table` `/form` `/input` `/button` |
| 3.3 ASCII Art | ASCII | `/box` `/line` `/arrow` `/tree` |
| 10 Scratchpad | General | `/date` `/time` `/separator` |

Commands are registered in each module's own initialisation path — Foundation owns the registry interface, not the command content (SR-1).

### Vibe Coding Rules check
- **SR-1** `SlashCommandRegistry` and `SlashCommandPopup` in Foundation; command *content* defined in each consumer module.
- **SR-6** `SlashCommand`, `SlashCommandRegistry`, `SlashCommandPopup` — three separate files.
- **SW-1** `matches(for:)` is synchronous (in-memory filter — appropriate; no async needed).
- **SW-2** `NSTextView` delegate's popup-state capture uses `[weak self]`.
- **SW-3** `SlashCommandPopup` is SwiftUI; integration with `NSTextView` via an overlay positioned using `NSTextView.firstRect(forCharacterRange:actualRange:)` converted to SwiftUI coordinates.
- **SW-4** `///` comments on `SlashCommandRegistry.register(_:)` and `matches(for:)`.

### Module guide changes
- **2.7 Utilities** — add `SlashCommand`, `SlashCommandRegistry` to key types and consumers table.
- **2.4 UI/UX** — add `SlashCommandPopup` to key types.
- **3 Text Editor / 3.1 Text** — add slash-trigger integration note; note command registration in module init.
- **10 Scratchpad** — add slash-trigger integration note.

### Commit
`[F-7] Universal slash-command auto-complete for editor and scratchpad`

---

## F-8 — Terminal Model Detection → Status Bar

### What
When the user loads an AI model via the Sputnik terminal (e.g. runs `claude`, `ollama run llama3`), detect the model name and show it in the status bar alongside its context window size. If the detected model is a Claude model **and** the Claude Code Status Line data file is present, also show:
- **5-hour token usage %**
- **Total weekly token usage %**

Both Claude-specific metrics vanish if the Status Line data file is absent or stale — no placeholder shown.

### Status bar with F-8 active
```
[ 🛰  ]  claude-sonnet-4-6   CTX 34%   │  llama3 (terminal)  CTW 8k   │  RAM 48 MB   CPU 2.1%
                                          ↑ terminal model segment        ↑ shown only if model detected in terminal

Claude model in terminal with Status Line loaded:
[ 🛰  ]  claude-sonnet-4-6   CTX 34%   │  claude-opus-4-8 (term)  CTW 200k   5hr 12%   wk 8%   │  RAM …
```

### Design decisions
- Terminal model display is a **separate segment** from the Settings-configured model — they are independent (one is the API model Sputnik will call; the other is a model the user is running interactively in the terminal).
- If no model is detected in the terminal, the terminal segment is hidden entirely.
- Claude Code Status Line metrics are shown only when **both** conditions are met: detected model is a known Claude model ID, and the status data file exists with a timestamp less than 30 s old.

### New types

**`TerminalModelInfo`** (`Sendable`, `2 Foundation/2.2 Global State Management/TerminalModelInfo.swift`):
```swift
struct TerminalModelInfo: Sendable {
    let name: String              // e.g. "claude-opus-4-8", "llama3"
    let contextWindow: Int?       // from ModelCapacity table; nil if unknown
    let claudeUsage: ClaudeStatusLineUsage?  // nil if not Claude or Status Line absent
}

struct ClaudeStatusLineUsage: Sendable {
    let fiveHourPercent: Double   // 0–100
    let weeklyPercent: Double     // 0–100
    let capturedAt: Date          // used to detect staleness (> 30 s → discard)
}
```
Stored as `AppState.terminalModelInfo: TerminalModelInfo?` — nil when no model is active in the terminal.

**`TerminalModelDetector`** (`@Observable @MainActor`, `2 Foundation/2.7 Utilities/TerminalModelDetector.swift`) — subscribes to the existing terminal output stream (via `AppState` / inter-panel protocol, not directly into module 7 internals — SR-1). Applies lightweight pattern matching to output lines to detect model-loading events:

| Pattern matched | Detected model |
|---|---|
| Output contains `✻ Welcome to Claude Code` | claude — resolve exact model from `~/.claude/settings.json` if present |
| Input line matches `ollama run <name>` | `<name>` |
| Output matches `loaded model: <name>` (ollama server log) | `<name>` |

When a model is detected: looks up `ModelCapacity.contextWindow(for:)` (F-3); if Claude, starts `ClaudeStatusLineReader`. Sets `AppState.terminalModelInfo`.

When the terminal session resets or the model process exits (detected by a shell prompt reappearing after the model session): clears `AppState.terminalModelInfo`.

**`ClaudeStatusLineReader`** (`@MainActor`, `2 Foundation/2.7 Utilities/ClaudeStatusLineReader.swift`) — polls `~/.claude/stats.json` (or the actual Claude Code status data path) every 5 s using a `Task(priority: .background)` loop. Parsing:
- If the file does not exist → Status Line is not loaded; `claudeUsage = nil`.
- If the file exists but `capturedAt` is more than 30 s old → treat as stale; `claudeUsage = nil`.
- If the file is fresh → decode `fiveHourPercent` and `weeklyPercent`; update `AppState.terminalModelInfo.claudeUsage`.

File watching uses `DispatchSource.makeFileSystemObjectSource` (the only available API for watching a single file for write events) with a comment at the call site per MR-3 justifying the `DispatchQueue` bridge.

### StatusBarView changes
Add a conditional terminal model segment between the AI model segment and the RAM segment:
```swift
if let info = appState.terminalModelInfo {
    Divider()
    Text("\(info.name) (term)")
    if let ctw = info.contextWindow {
        Text("CTW \(formatContextWindow(ctw))")
    }
    if let usage = info.claudeUsage, usage.capturedAt.timeIntervalSinceNow > -30 {
        Text("5hr \(Int(usage.fiveHourPercent))%")
        Text("wk \(Int(usage.weeklyPercent))%")
    }
}
```

### Vibe Coding Rules check
- **SR-1** `TerminalModelDetector` subscribes to terminal output via the Foundation inter-panel protocol — it does not import or reference module 7 types directly. `TerminalModelInfo`, `ClaudeStatusLineUsage`, `AppState.terminalModelInfo` all in Foundation.
- **SR-2** `JSONDecoder` on the stats file can throw — caught; failure sets `claudeUsage = nil`, no crash. File read via `Data(contentsOf:)` — wrapped in `do/catch`.
- **SR-4** File polling in `Task(priority: .background)`; `DispatchSource` handler dispatches to `@MainActor` before writing state.
- **SR-5** `DispatchSource.makeFileSystemObjectSource` — native Apple API; no third-party file-watcher.
- **SR-6** `TerminalModelDetector`, `ClaudeStatusLineReader`, `TerminalModelInfo` — three separate files.
- **SW-1** Polling loop uses `Task` + `Task.sleep`; `DispatchSource` bridge is documented at call site (MR-3 exception).
- **SW-2** `[weak self]` in the `Task` polling body and in the `DispatchSource` event handler — both are long-lived.
- **SW-3** `StatusBarView` extension is pure SwiftUI.
- **MR-2** Terminal output stream observed via the existing `NSFilePresenter`/`AsyncStream` mechanism in module 7 — no new file-system polling introduced for terminal output.

### Module guide changes
- **2.2 Global State** — add `terminalModelInfo: TerminalModelInfo?`, `TerminalModelInfo`, `ClaudeStatusLineUsage` to AppState owned-state list.
- **2.4 UI/UX** — add terminal model segment to `StatusBarView` description; update layout/status-bar diagram.
- **2.7 Utilities** — add `TerminalModelDetector`, `ClaudeStatusLineReader` to key types and consumers table.
- **7 Terminal** — add note that terminal output stream is observable by Foundation via inter-panel protocol; no module-7-internal changes required.

### Commit
`[F-8] Terminal model detection — model name, context window, and Claude Status Line metrics in status bar`

---

## New Issues Logged (ISS-012 – ISS-014)

See `References/Issues.md` for the formal entries. Summary:

| ID | Module | Problem | Resolved by |
|---|---|---|---|
| ISS-012 | 2.3 Settings / 3 Text Editor | `editorFont` is a single global token; per-panel overrides risk a second source of truth | F-4 computed resolvers |
| ISS-013 | 2.2 Global State / 2.4 UI/UX | No `AppState.isProcessing` flag for status bar animation and menu-bar item | F-5 processing counter |
| ISS-014 | 2.3 Settings / Security | No Keychain bridge; API keys would land in `UserDefaults` insecurely | F-3 `KeychainService` |

---

## Plan Completion

After F-8 is committed and pushed:
1. Change `Status: New` at the top of this file to `Status: Complete`.
2. Move this file: `1 Setup/Plans New/` → `1 Setup/Plans Completed/`.
3. Final commit: `[Plan] Mark Eight New Features plan complete`.
