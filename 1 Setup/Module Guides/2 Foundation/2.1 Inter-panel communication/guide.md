---
module: 2.1 Foundation – Inter-panel Communication
status: active
last_updated: 2026-06-08
---

## Purpose
Route file-open events and directory changes from any panel to the correct destination panel, so all modules stay coordinated without calling each other directly.

## Diagram

```
File open event (from module 6)
         │
         ▼
  InterPanelRouter (protocol, registered in Foundation)
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
                   └──▶ error dialog (Foundation 2.4)

Directory change event (from module 6 or module 7)
         │
         ▼
  InterPanelRouter.syncDirectory(_ url: URL)
         └──▶ AppState.activeWorkspaceDirectory   (module 2.2)
                   └──▶ Terminal (7) observes and calls `cd <url>`
```

## Technical Summary
- **Framework(s):** Foundation, Swift Concurrency
- **Key types:**
  - `InterPanelRouter` — protocol defining `open(_ file: URL)` and `syncDirectory(_ url: URL)`; registered in Foundation, never implemented here <!-- assumed -->
  - `FileType` — enum classifying a URL by extension (`.text`, `.markdown`, `.html`, `.pdf`, `.ascii`, `.binary`, `.unknown`) <!-- assumed -->
  - `PanelEvent` — enum of events broadcast to observers (`fileOpened(URL, FileType)`, `directoryChanged(URL)`) <!-- assumed -->
- **Threading model:** All routing decisions run on `@MainActor`. File-type classification (extension lookup) is synchronous and cheap — no background dispatch needed.
- **Data flow:** File Tree (6) calls `InterPanelRouter.open(_:)` → router classifies the URL as a `FileType` → posts a `PanelEvent` via `AsyncStream` → destination module observes the stream and loads the file.
- **State owned:** None. This module is a pure router — it holds no file content and owns no persistent state. It reads `AppState` (2.2) to update the active directory but does not own it.
- **Dependencies:** `AppState` (2.2) for directory sync; error dialog types from UI/UX (2.4).
- **Failure modes:**
  - Unrecognised file type → classified as `.unknown` → error dialog presented; no crash.
  - Binary or oversized file → classified as `.binary` → editor refuses to open (module 3 enforces the size limit); router logs and surfaces the error.
  - No module registered for a `FileType` → router logs a warning and shows an error dialog; does not assert or force-unwrap.

## Spec Reference
> Extracted verbatim from `readme.md`:

```
  1. Inter-panel communication
    1. File Association & Routing
    2. Directory Synchronization
```
