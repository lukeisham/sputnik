---
module: 2.1 Foundation – Inter-panel Communication
status: active
last_updated: 2026-06-08
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

## Technical Summary
- **Framework(s):** Foundation, Swift Concurrency
- **Key types:**
  - `InterPanelRouter` — `@MainActor` protocol with `open(_:)`, `close(_:)`, and
    `syncDirectory(_:)`; registered in Foundation, never implemented here
  - `FileType` — enum classifying a URL by extension (`.text`, `.markdown`, `.html`,
    `.pdf`, `.ascii`, `.binary`, `.unknown`); defined here, shared with module 2.2
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

## Spec Reference
> Extracted verbatim from `readme.md`:

```
  1. Inter-panel communication
    1. File Association & Routing
    2. Directory Synchronization
```
