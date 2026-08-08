---
module: 2.10 Foundation – Templates
status: active
last_verified: 2026-06-16
last_updated: 2026-06-16
---

## Purpose

Provide a template library so users can quickly create new documents from saved boilerplate files, with `{{placeholder}}` expansion, managed from the File menu and configured via Settings.

## Purpose check

Sputnik is "a native macOS simplified development environment... designed for focused AI agent management, and personal productivity."

Templates directly serve **personal productivity**: they eliminate repetitive boilerplate setup before writing, which is especially valuable in a focused single-window environment where starting a new document should be instant. **Pass.**

## Diagram

```
  File Menu                    Settings › Templates tab
  ─────────                    ────────────────────────
  Open Template ▶              templateDirectoryURL (SettingsStore)
  Save As Template ⌃⌘S               │
  Remove Template ▶                   │ setTemplateDirectoryURL(_:)
         │                            │
         ▼                            ▼
  AppState (@MainActor)        AppState.applyTemplateDirectory(_:)
  ─────────────────                   │
  availableTemplates []               │ setDirectory(_:)
  templatePendingRequest?             ▼
  templateError?              ┌────────────────────────────┐
         │                    │  TemplateStore (actor)     │
         │ openTemplate()     │  directoryURL: URL         │
         │                    │  templates()               │
         │                    │  save(name:content:ext:)   │
         ▼                    │  delete(record:)           │
  TemplatePendingRequest      │  rawContent(of:)           │
  { record, rawContent }      │  bootstrap()               │
         │                    └────────────────────────────┘
         ▼                            ▲
  TemplatePlaceholderSheet            │ shared singleton
  (ContentView .sheet)        ────────────────────────────
         │                    ~/Library/Application Support/
         │ onConfirm          Sputnik/Templates/  (default)
         ▼
  TemplatePlaceholderExpander
  placeholders(in:) → [String]
  expand(template:values:) → String
  defaultValues(for:) → [String:String]
         │
         ▼
  AppState.openTemplateDocument(content:fileExtension:)
  → DocumentSession(url: nil, fileType:, text:, isDirty: true)
  → WindowState.openDocuments.append(session)
```

## Source Files

| File | Responsibility |
|---|---|
| `2.10 Templates/TemplateRecord.swift` | `TemplateRecord` — `Identifiable, Hashable, Sendable` value type; `id: URL`, `name`, `fileExtension` derived from the URL at init |
| `2.10 Templates/TemplateStore.swift` | `actor TemplateStore` — shared singleton; manages the template directory (default or user-set); CRUD: `templates()`, `save(name:content:fileExtension:)`, `delete(record:)`, `rawContent(of:)`, `setDirectory(_:)`, `bootstrap()` |
| `2.10 Templates/TemplatePlaceholderExpander.swift` | `enum TemplatePlaceholderExpander` — pure static functions: `placeholders(in:) → [String]`, `expand(template:values:) → String`, `defaultValues(for:) → [String:String]`; regex pattern compiled once as `static let` |
| `2.10 Templates/TemplatePlaceholderSheet.swift` | `TemplatePendingRequest` — `Identifiable Sendable` struct carrying the selected `TemplateRecord` and its raw content; drives `.sheet(item:)` in `ContentView`. `TemplatePlaceholderSheet` — SwiftUI sheet that shows one `TextField` per `{{key}}` placeholder; dates pre-filled; "Open" disabled until all non-date keys filled |

## Technical Summary

- **Framework(s):** Foundation, SwiftUI
- **Key types:**
  - `TemplateRecord` (`Sendable Identifiable Hashable`) — lightweight value type; `id` is the file URL; `name` and `fileExtension` derived at init; no mutable state
  - `TemplateStore` (`actor`, shared singleton) — all file I/O is actor-isolated; holds `var directoryURL: URL`; `bootstrap()` creates the directory and seeds two starter templates (`.md`, `.html`) if the directory is empty; `rawContent(of:)` reads lazily per call and never caches beyond the caller's scope (SR-3); seeder uses hardcoded strings — no bundle resources required
  - `TemplatePlaceholderExpander` (uninstantiable `enum`) — pure static functions; `NSRegularExpression` pattern compiled once as `static let` to avoid repeated compilation (cf. ISS-122); `defaultValues(for:)` seeds `{{date}}` → today's ISO date via `DateFormatter`
  - `TemplatePendingRequest` (`Identifiable Sendable`) — transient struct created by `AppState.openTemplate(record:)` and consumed by `TemplatePlaceholderSheet`; nil-ed out after sheet dismissal
  - `TemplatePlaceholderSheet` (`View`) — accepts a `TemplatePendingRequest` and an `onConfirm: ([String:String]) -> Void` closure; auto-confirms without showing if the template has no placeholders (handled before creation in `AppState.openTemplate`)
- **Threading model:** `TemplateStore` is an actor — all directory scans, reads, writes, and deletes run off the main thread; `AppState` calls into it with `await`; `TemplatePlaceholderExpander` is pure and can run on any thread; `TemplatePlaceholderSheet` and `TemplatePendingRequest` are `@MainActor`-resident via SwiftUI
- **Data flow:**
  1. On launch: `SputnikApp.onAppear` → `TemplateStore.shared.bootstrap()` → `AppState.applyTemplateDirectory(settings.templateDirectoryURL)` → `TemplateStore.setDirectory(_:)` + `AppState.refreshTemplates()` → `AppState.availableTemplates` updated → File menu rebuilds
  2. User selects "Open Template › name": `AppState.openTemplate(record:)` → reads raw content → if no placeholders: `openTemplateDocument(content:fileExtension:)` directly; if placeholders: sets `templatePendingRequest` → `ContentView .sheet` appears → user fills fields → `TemplatePlaceholderExpander.expand` → `openTemplateDocument`
  3. User clicks "Save As Template": `saveAsTemplate(appState:)` in `MenuHelpers` → `NSAlert` text-field → `AppState.saveCurrentAsTemplate(name:)` → `TemplateStore.save` → `refreshTemplates()`
  4. Settings change: `TemplatesTab` → `settings.setTemplateDirectoryURL(url)` → `AppState.applyTemplateDirectory(url)` → `TemplateStore.setDirectory(url)` + `refreshTemplates()`
- **State owned:**
  - `TemplateStore` owns `directoryURL` (actor-isolated)
  - `AppState` owns `availableTemplates: [TemplateRecord]`, `templatePendingRequest: TemplatePendingRequest?`, `templateError: SputnikAlert?`
  - `SettingsStore` owns `templateDirectoryURL: URL?` (persisted as path string in `UserDefaults`)
- **Dependencies:** `FoundationModule` types only (`SputnikAlert`, `FileType`, `DocumentSession`, `AppState`, `SettingsStore`); no dependency on modules 3–9
- **Failure modes:** directory unreadable → `templates()` returns `[]`; file read fails → `SputnikAlert.fileReadFailed` stored in `AppState.templateError`, shown via `ContentView` alert; save collision → `SputnikAlert.custom` thrown, caught in `saveAsTemplate` helper, shown via `presentAlert`; trash fails → `SputnikAlert.fileWriteFailed` thrown, caught in `FileMenuGroup`

## Invariants

- `TemplateStore` is the **only** type that reads from or writes to the template directory; no other type touches those files directly (SR-1)
- `TemplateStore.rawContent(of:)` reads per call and never retains content in memory beyond the return value (SR-3)
- `TemplatePlaceholderExpander` has no state and no side effects — all functions are `static`
- `AppState.openTemplateDocument` follows the same session lifecycle as `WindowState.newUntitledDocument`: `url: nil`, `isDirty: true`, appended to `activeWindow.openDocuments`
- `TemplateStore.shared.bootstrap()` is safe to call multiple times — directory creation and seeding are both guarded by existence checks

## Known consumers

| Module | Use |
|---|---|
| 2.0 App Overview (`FileMenuGroup`) | "Open Template ▶", "Save As Template ⌃⌘S", "Remove Template ▶" menus |
| 2.0 App Overview (`MenuHelpers`) | `saveAsTemplate(appState:)` helper |
| 2.2 Global State (`AppState`) | Template state + actions (owns `availableTemplates`, `templatePendingRequest`, `templateError`) |
| 2.3 Settings (`SettingsStore`) | `templateDirectoryURL` preference |
| App-Sputnik (`ContentView`) | `.sheet(item: templatePendingRequest)` + template error alert |
| App-Sputnik (`TemplatesTab`) | Settings UI for folder picker |
| App-Sputnik (`SputnikApp`) | Calls `bootstrap()` + `applyTemplateDirectory` at launch |

## Spec Reference

> No spec bullet existed in `readme.md` at the time this module was created (2026-06-16).
> The module was designed and added in response to a direct user request. The canonical
> design intent is captured in this guide and in
> `1 Setup/Plans New/2026-06-16 2.10 Foundation Add Templates.md`.
