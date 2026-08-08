---
title: Misc Improvements — Save as PDF & Image Drag from File Tree
status: plan
created: 2026-06-12
modules_affected:
  - 3 Text Editor Window
  - 4 Markdown Preview
  - 5 PDF Viewer
  - 6 Project File Tree
  - 8 HTML Preview
  - 2 Foundation (minor — PanelEvent, FileType)
open_issues: none yet
---

## Overview

Two self-contained improvements to Sputnik's editor and preview workflows:

1. **Save as PDF** — add a "Save as PDF…" action to the Markdown Preview, HTML Preview, and Text Editor panels, exporting the rendered/edited content to a PDF file on disk.
2. **Image drag from File Tree → Editor** — dragging an image file (PNG, JPEG, GIF, etc.) from the Project File Tree into the active text editor opens it in the PDF Viewer (which already supports image display) and inserts an `![](path)` or `<img src="path">` markup into the editor.

Neither feature requires new third-party dependencies — everything maps onto existing macOS frameworks (PDFKit, WKWebView `PDFConfiguration`, FileManager, NSItemProvider, NSPasteboard).

---

## Feature 1 — Save as PDF

### What it does

Adds a **"Save as PDF…"** button to:
- **Markdown Preview** (overflow menu or toolbar)
- **HTML Preview** (overflow menu or toolbar)
- **Text Editor** (File menu and/or editor overflow menu)

On click, a save panel appears (`NSSavePanel` with `.pdf` filter). The chosen content is rendered to a PDF document and written atomically.

### How each panel generates the PDF

| Panel | Source | PDF generation mechanism |
|---|---|---|
| **Markdown Preview** | The already-rendered `NSAttributedString` | Wrap it in an `NSTextView`, compute layout, draw pages via `NSPrintOperation` + PDF options, or use `PDFDocument` by drawing each page. Simpler path: `NSTextView.printView` with `NSPrintInfo` set to PDF output. |
| **HTML Preview** | The `WKWebView`'s rendered page | `WKWebView.createPDF(configuration:)` — the modern API. A `WKPDFConfiguration` with `.fitToPage = true` gives a well-paginated result. |
| **Text Editor** | The plain-edited `String` / `NSTextView` content | Same mechanism as Markdown — print the `NSTextView` to PDF via `NSPrintOperation` with `NSPrintInfo.jobDisposition = NSPrintSpoolJob`. |

### Implementation plan

#### 1a. Markdown Preview — "Save as PDF…" action

**Files:** `MarkdownPreviewPanel.swift`, `MarkdownPreviewViewModel.swift`

- Add a **"Save as PDF…"** menu item in the overflow menu (the `ellipsis` `Menu` in `headerBar`).
- On selection, call `viewModel.saveAsPDF()` which:
  1. Opens an `NSSavePanel` with `allowedContentTypes = [.pdf]`.
  2. Creates a temporary `NSTextView`, sets its `attributedString` to `renderedString`, lays it out at the same fit-width / font-scale as the preview.
  3. Creates `NSPrintOperation` with `NSPrintInfo` configured for PDF output:
     - `jobDisposition = .spool`
     - `outputFormat = .pdf`
     - `orientation` and paper size from the panel's fit-width settings.
  4. Writes the PDF to the user-chosen URL.

**Failure paths:**
- No rendered content → show alert "Nothing to export."
- Print operation fails → catch the error and show a `SputnikAlert`.

#### 1b. HTML Preview — "Save as PDF…" action

**Files:** `HTMLPreviewPanel.swift`, `HTMLPreviewView.swift`

- Add a **"Save as PDF…"** menu item in the overflow menu.
- On selection, call a method on `HTMLPreviewView` (which holds the `WKWebView`):
  1. Open an `NSSavePanel`.
  2. Call `webView.createPDF(configuration:)` with a `WKPDFConfiguration(fitToPage: true)`.
  3. Write the returned `Data` to the chosen URL.

**Failure paths:**
- No active document → alert.
- `createPDF` fails (should be rare) → show load error banner.

#### 1c. Text Editor — "Save as PDF…" action

**Files:** `EditorView.swift` or a new `EditorCommandHandling` method, `EditorViewModel.swift`

- Add a **File → Save as PDF…** menu command (via `EditorCommandHandling` — `saveAsPDF()`).
- The command calls into `EditorViewModel`:
  1. Opens an `NSSavePanel`.
  2. Uses the active `NSTextView`'s text storage, creates a print operation with `NSPrintInfo` set to PDF output.
  3. Writes the PDF to the chosen URL.

**Failure paths:**
- No active document / empty buffer → alert.
- Print failure → alert.

#### 1d. (Optional) ASCII Studio panel

If the ASCII Studio panel (module 10) has a rendered view, a similar PDF export could be added later. Out of scope for this pass.

---

## Feature 2 — Image Drag from File Tree to Editor

### What it does

When a user drags an image file (PNG, JPEG, GIF, HEIC, BMP, TIFF) from the **Project File Tree** and drops it onto the **Text Editor**:

1. The image file opens as a preview in the **PDF Viewer** (which already has `loadImage()` for PNG/JPEG display).
2. A text insertion is made into the active text editor:
   - If the active editor is inside a **Markdown** context (`.md` file, or `.markdown` editor mode) → insert `![filename](relative-path)`.
   - If the active editor is inside an **HTML** context (`.html` file, or HTML mode) → insert `<img src="relative-path" alt="filename">`.
   - If the editor is in any other mode → insert the **Markdown** syntax by default (it's the least surprising fallback).

### How drag-and-drop works in the current codebase

- **FileTreePanel** already has an `.onDrop(of: [UTType.fileURL])` handler that handles external drops into the tree for file copying/moving.
- **FileTreeRowView** (an `NSViewRepresentable` wrapping an `NSTableRowView` or similar) is the per-row view. Each row represents a `FileTreeNode`.
- **EditorTextView** (a subclass of `NSTextView`) gets standard `NSDraggingDestination` methods. SwiftUI's `EditorView` wraps this.

### Implementation plan

#### 2a. Enable drag source on FileTreeRowView

**Files:** `FileTreeRowView.swift`, `FileTreeNode.swift`

- Each `FileTreeRowView` (or the `NSViewRepresentable` that creates it) must register itself as a **drag source** (`NSDraggingSource`).
- When a drag begins on an image-type file node, create an `NSItemProvider` containing:
  - The file URL (`.fileURL` type identifier).
  - A string representation: the Markdown `![alt](path)` or HTML `<img>` syntax (computed lazily so the drop target can choose which representation it wants).
- For non-image files, no drag is started (or the default `NSTableView` drag behaviour is suppressed).

**Key decisions:**
- The drag is initiated on the row view, not the entire tree. This keeps it clean: each row knows what file it represents.
- Only image files (`.png`, `.jpg`, `.jpeg`, `.gif`, `.heic`, `.bmp`, `.tiff`) should initiate a drag. Others are either ignored or left for future file-drag support.

#### 2b. Handle the drop in EditorTextView

**Files:** `EditorTextView.swift`, `EditorView.swift`

- `EditorTextView` (an `NSTextView` subclass) already inherits `NSDraggingDestination` from `NSTextView`. Override:
  - `draggingEntered(_:)` → check if the pasteboard has a `.fileURL` item and a known image UTType. Return `.copy` if so, `.none` otherwise.
  - `draggingUpdated(_:)` → return `.copy` if still valid.
  - `performDragOperation(_:)` → the core logic:
    1. Read the file URL from the pasteboard.
    2. Determine the file type. If it's an image:
       a. **Open in PDF Viewer**: Call `InterPanelRouter.open(url)` — the router's `.image` handling already routes to the PDF Viewer, which calls `loadImage()`.
       b. **Insert markup into editor**: Determine the current editor mode (`EditorViewModel.mode`):
          - `.markdown` → insert `![filename](relative-path)` where `relative-path` is computed relative to the editor's open file directory (or absolute if no file is open).
          - `.html` → insert `<img src="relative-path" alt="filename">`.
          - `.plainText`, `.asciiArt`, or others → default to Markdown syntax (it's readable in any context).
    3. If the dragged file is **not** an image → no-op (call `super.performDragOperation` or return `.none`).

#### 2c. Compute relative path for the inserted markup

- If the editor has a file open (`editorViewModel.fileURL`), compute the relative path from the editor's directory to the image file.
- If no file is open (untitled document), use either:
  - The absolute file path (least surprising for a new document).
  - The filename only (simpler, but ambiguous if images share names).
  → **Recommendation:** use the absolute path when no workspace context exists, the relative path when it does. This matches what a user would expect from "drop an image here".

#### 2d. Update FileType routing if needed

**Files:** `FileType.swift` (in Foundation 2.1)

- The current `FileType` enum has an `.image` case and `FileType(url:)` maps `png`, `jpg`, `jpeg` to `.image`. Verify that `gif`, `heic`, `bmp`, `tiff` also map to `.image` (they map to `.binary` currently in some cases — see `FileType.swift` line 26-28). Update if needed so common image types route correctly through the PDF viewer.
- The `InterPanelRouter.open(_:)` implementation should already route `.image` to the PDF Viewer (via `AppState` observing the active document's fileType). Verify this during implementation.

### Failure paths for Feature 2

- Pasteboard read fails → silently abort (standard drag behaviour).
- Image file doesn't exist at path → `InterPanelRouter.open` handles the missing-file case downstream.
- PDF Viewer shows error → the viewer's existing error states (`errorView`) cover this.
- Editor has no active session → the drop is silently rejected (return `.none`).

---

## Ordering & Dependencies

| Step | Feature | Depends on | Effort |
|---|---|---|---|
| 1a | Markdown Preview "Save as PDF" | Nothing | Medium |
| 1b | HTML Preview "Save as PDF" | Nothing | Small |
| 1c | Text Editor "Save as PDF" | Nothing | Medium |
| 2a | FileTreeRowView drag source | Nothing | Medium |
| 2b | EditorTextView drop handling | 2a | Medium |
| 2c | Relative path computation | 2b | Small |
| 2d | FileType routing update | Nothing | Small |

Features 1 and 2 are fully independent — they can be worked on in parallel.

**Recommended order for Feature 1:** 1b (HTML Preview is simplest) → 1a (Markdown) → 1c (Text Editor).

**Recommended order for Feature 2:** 2d (quick FileType fix) → 2a (drag source) → 2b + 2c (drop + path computation).

---

## Risks & Open Questions

1. **FileType routing for images** — Confirm that `FileType.image` is correctly routed to `PDFViewerPanel.loadImage()` by the `InterPanelRouter` / `AppState.activeDocument` observation path. Currently `PDFViewerPanel.handleActiveDocumentChange()` only checks for `.pdf` and does nothing for `.image`. This needs to be updated to call `viewModel.loadImage(url)` when `fileType == .image`.
2. **NSDraggingSource on SwiftUI view** — `FileTreeRowView` is likely an `NSViewRepresentable`. The drag source registration must happen in `makeNSView` or `updateNSView`. If the row view is a plain SwiftUI `View` inside a `ForEach`, consider wrapping it in a custom `NSViewRepresentable` that acts as both the drag source and destination.
3. **Markdown vs HTML context detection** — For the editor, detect "inside an HTML codeblock" as the spec suggests. This requires checking the syntax scope at the insertion point. If the editor is in `.html` mode, use `<img>`. If in a Markdown code block, that's a Markdown code block, not HTML. Since the NSTextView doesn't expose per-character syntax scope via a simple API, the pragmatic approach is to use the editor mode (`.markdown` vs `.html`) as the heuristic, which covers >95% of cases.

---

## Test Plan

- **Feature 1:** (manual) Open a `.md`, `.html`, and `.txt` file. Click "Save as PDF…" in each panel. Verify the output PDF renders correctly.
- **Feature 2:**
  - Drag a `.png` from the File Tree to the Editor → verify the PDF Viewer opens the image and the editor gets `![filename](path)` inserted.
  - Repeat for `.jpg`, `.gif`, `.heic`.
  - Drag a `.pdf` (non-image) → verify nothing happens.
  - Drag from outside the app (Finder) → verify existing `.onDrop` still works (file copy behaviour).
  - Open an `.html` file, drag an image → verify `<img src="path">` is inserted instead of Markdown.
