---
module: 2.1 Foundation – Inter-panel Communication
status: stable
last_updated: 2026-06-12
last_verified: 2026-06-12
---

## Purpose
Route file-open, file-close, and directory-change events from any panel to the correct
destination so all modules stay coordinated without calling each other directly.

## Diagram

```
File open event (from module 6 or from a link click in module 8)
         │
         ▼
  InterPanelRouter.open(_:)  [find-or-create semantics]
         │
         ├── Session already open for URL?
         │         └──▶ make existing session active (raise panel)
         │
         └── New session:
               classify FileType from extension
               append DocumentSession to AppState.openDocuments
               set AppState.activeDocumentID
               │
               ├── .text / .markdown / .html / .ascii
               │         └──▶ Text Editor Window (3)
               │                    └──▶ Markdown Preview (4)  [if .markdown]
               │                    └──▶ HTML Preview (8)      [if .html]
               │
               ├── .pdf
               │         └──▶ PDF Viewer (5)
               │
               └── .unknown / .binary
                         └──▶ SputnikAlert error dialog (Foundation 2.4)

File close event
         │
         ▼
  InterPanelRouter.close(_ id:)
         │
         ├── isDirty == true?  →  SputnikAlert unsaved-changes prompt
         │         └── confirmed → remove session, update activeDocumentID
         │         └── cancelled → no-op
         │
         └── isDirty == false → remove session, activate neighbouring tab

Directory change event (from module 6 or module 7)
         │
         ▼
  InterPanelRouter.syncDirectory(_ url:)
         └──▶ AppState.activeWorkspaceDirectory
                   └──▶ Terminal (7) observes and calls `cd <url>`
```

## Source Files
| File | Responsibility |
|---|---|
| `InterPanelRouter.swift` | `@MainActor` protocol — `open(_:)`, `close(_:)`, `syncDirectory(_:)`, `events: AsyncStream<PanelEvent>` |
| `AppInterPanelRouter.swift` | `@MainActor` class — concrete implementation of `InterPanelRouter`; find-or-create open semantics, dirty-tab close guard (ISS-020), directory sync |
| `FileType.swift` | `Codable Sendable` enum — classifies URLs by extension: `.text`, `.markdown`, `.html`, `.pdf`, `.ascii`, `.image`, `.binary`, `.unknown` |
| `PanelEvent.swift` | `Sendable` enum — `fileOpened(URL, FileType)`, `directoryChanged(URL)` |

## Technical Summary
- **Framework(s):** Foundation, Swift Concurrency
- **Key types:**
  - `InterPanelRouter` — `@MainActor` protocol with `open(_:)`, `close(_:)`, `syncDirectory(_:)`, and `events: AsyncStream<PanelEvent>`; registered in Foundation, concrete implementation is `AppInterPanelRouter`
  - `AppInterPanelRouter` — `@MainActor` concrete class implementing `InterPanelRouter`; find-or-create open semantics, dirty-tab guard on close (ISS-020), directory sync, `moveActiveTabToNewWindow()` with unsaved-changes prompt
  - `FileType` — `Codable Sendable` enum classifying a URL by extension (`.text`, `.markdown`, `.html`, `.pdf`, `.ascii`, `.image`, `.binary`, `.unknown`); defined here, shared with module 2.2; includes `.image` for PNG/JPEG routing (ISS-048)
  - `PanelEvent` — `Sendable` enum of events broadcast via `AsyncStream<PanelEvent>`
    (`fileOpened(URL, FileType)`, `directoryChanged(URL)`)
- **`open(_:)` contract — find-or-create:**
  1. If `AppState.openDocuments` already contains a session with the given URL, make
     that session active. No duplicate tab is created.
  2. Otherwise, create a new `DocumentSession`, append it, and set it active.
- **`close(_:)` contract:**
  - Runs the `isDirty` guard before removing.
  - After removal, sets `activeDocumentID` to the neighbouring tab, or `nil` if empty.
- **Threading model:** All routing decisions run on `@MainActor`. File-type classification
  (extension lookup) is synchronous and cheap — no background dispatch needed.
- **Data flow:** File Tree (6) calls `open(_:)` → router classifies URL as `FileType`
  → appends/activates `DocumentSession` in `AppState` → posts `PanelEvent` via
  `AsyncStream` → destination module observes and renders the active session.
- **State owned:** None. This module is a pure router — it mutates `AppState` (2.2) but
  holds no file content or persistent state of its own.
- **Dependencies:** `AppState` (2.2) for document list and directory sync;
  `SputnikAlert` (2.4) for error dialogs; `DocumentSession` (2.2) for session identity.
- **Failure modes:**
  - Unrecognised type → `.unknown` → `SputnikAlert` dialog; no crash.
  - Binary/oversized file → `.binary` → editor refuses to open (module 3 enforces size
    limit); router logs and surfaces the error.
  - No module registered for a `FileType` → router logs a warning and shows a dialog;
    does not assert or force-unwrap.
  - `close(_:)` called with an `id` not in `openDocuments` → no-op.

## Invariants
- `InterPanelRouter` and `AppInterPanelRouter` are `@MainActor` — all routing decisions mutate `AppState` synchronously on the main thread (SW-1)
- `FileType` classification is a pure function of the URL extension — no disk I/O involved (SR-4)
- The `open(_:)` contract guarantees **find-or-create**: no duplicate tabs for the same URL
- The `close(_:)` contract runs the `isDirty` guard before removing — unsaved changes are never silently discarded (SR-2)
- Modules never call `AppState.openDocuments` or `WindowState.openDocument` directly — all file-open events flow through `InterPanelRouter.open(_:)` (SR-1, SC-9)
- `moveActiveTabToNewWindow()` shows an `NSAlert` confirmation when `session.isDirty`; returns `nil` on cancel (ISS-020)

## Spec Reference
> Extracted verbatim from `readme.md`:

```
  1. Inter-panel communication
    1. File Association & Routing
    2. Directory Synchronization
```
