---
module: 5 PDF Viewer
status: complete
last_updated: 2026-06-10
plan: 1 Setup/Plans New/2026-06-08 5 PDF Viewer Implement PDF Viewer module.md
---

## Purpose

The PDF Viewer renders Portable Document Format files using PDFKit, providing fixed-layout display, text selection, scaled/rotated viewing, a table-of-contents sidebar, and a thumbnail grid — all within a single panel in Sputnik's right slot.

## Diagram

```
PDF VIEWER PANEL  (occupies the right slot; see module 2.0 overview)
────────────────────────────────────────────────────────────────────

 ┌────────────────────────────────────────────────────────────────┐
 │  PDF TOOLBAR                                                    │
 │  [◀ Prev]  [Page 3 / 24]  [Next ▶]   [🔍−  100%  🔍+]  [↻]  │
 │                                              scale    rotate   │
 ├────────────────────────────────────────────────────────────────┤
 │                                                                │
 │   ┌────────────────────────────────────────────────────────┐   │
 │   │                                                        │   │
 │   │   ┌──────────────────────────────────────────────────┐ │   │
 │   │   │  Sputnik Design Doc                              │ │   │
 │   │   │  ═══════════════════                             │ │   │
 │   │   │                                                  │ │   │
 │   │   │  1. Introduction  . . . . . . . . . . . . .  1  │ │   │
 │   │   │  2. Architecture  . . . . . . . . . . . . .  4  │ │   │
 │   │   │  3. Modules  . . . . . . . . . . . . . . .  8  │ │   │
 │   │   │  4. Performance . . . . . . . . . . . . .  15  │ │   │
 │   │   │                                                  │ │   │
 │   │   │  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │ │   │
 │   │   │  ░░░░░    rendered page content      ░░░░░░░░   │ │   │
 │   │   │  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   │ │   │
 │   │   │                                                  │ │   │
 │   │   └──────────────────────────────────────────────────┘ │   │
 │   │                                                        │   │
 │   └────────────────────────────────────────────────────────┘   │
 │                                                                │
 ├────────────────────────────────────────────────────────────────┤
 │  STATUS BAR  (optional, toggled from View menu)                │
 │  [Page 3 of 24  |  File: spec.pdf  |  1.2 MB  |  100%  |  ▭]│
 └────────────────────────────────────────────────────────────────┘

 ┌──────────────────────┐   ┌────────────────────────────────────┐
 │  TOC SIDEBAR          │   │  THUMBNAILS SIDEBAR               │
 │  (toggle with TOC btn)│   │  (toggle with THUMB btn)          │
 │                       │   │                                   │
 │  ┌──────────────────┐ │   │  ┌─────┐ ┌─────┐ ┌─────┐        │
 │  │ ▸ 1. Introduction│ │   │  │ ░░░ │ │ ░░░ │ │ ░░░ │        │
 │  │ ▸ 2. Architecture│ │   │  │ ░░░ │ │ ░░░ │ │ ░░░ │        │
 │  │   ▸ 2.1 Overview │ │   │  │  p1  │ │  p2  │ │  p3  │        │
 │  │   ▸ 2.2 Layout   │ │   │  └─────┘ └─────┘ └─────┘        │
 │  │ ▸ 3. Modules     │ │   │  ┌─────┐ ┌─────┐ ┌─────┐        │
 │  │   ▸ 3.1 Core     │ │   │  │ ░░░ │ │ ░░░ │ │ ░░░ │        │
 │  │   ▸ 3.2 UI       │ │   │  │ ░░░ │ │ ░░░ │ │ ░░░ │        │
 │  │                  │ │   │  │  p4  │ │  p5  │ │  p6  │        │
 │  └──────────────────┘ │   │  └─────┘ └─────┘ └─────┘        │
 └──────────────────────┘   └────────────────────────────────────┘

 ┌─── DATA FLOW ──────────────────────────────────────────────────┐
 │                                                                 │
 │  File Tree              Foundation               PDF Viewer     │
 │  ──────────             ──────────               ──────────     │
 │  user clicks     ──►   InterPanelRouter    ──►   PDFViewerPanel │
 │  spec.pdf               .open(_:)                loads PDFDoc   │
 │                                                  via PDFKit     │
 │                                                    │            │
 │                              ┌─────────────────────┴──────┐     │
 │                              │  PDFDocument                │     │
 │                              │  ├── pages[0..N]            │     │
 │                              │  ├── outlineRoot  (TOC)     │     │
 │                              │  └── documentAttributes      │     │
 │                              └─────────────────────────────┘     │
 │                                                                 │
 │  User interactions:                                             │
 │  ┌────────────┐    ┌────────────────┐    ┌──────────────────┐  │
 │  │ Prev/Next  │───►│ PDFView.go(…)  │───►│ PDFView renders  │  │
 │  │            │    │                │    │ current page      │  │
 │  ├────────────┤    ├────────────────┤    ├──────────────────┤  │
 │  │ Zoom +/-   │───►│ PDFView.set    │───►│ PDFView reflow   │  │
 │  │            │    │ scaleFactor    │    │ display          │  │
 │  ├────────────┤    ├────────────────┤    ├──────────────────┤  │
 │  │ Rotate     │───►│ PDFView.rotate │───►│ PDFView rotates  │  │
 │  │            │    │ (right)        │    │ all pages        │  │
 │  ├────────────┤    ├────────────────┤    ├──────────────────┤  │
 │  │ Text       │───►│ PDFSelection   │───►│ clipboard copy   │  │
 │  │ Select     │    │                │    │ via NSPasteboard │  │
 │  └────────────┘    └────────────────┘    └──────────────────┘  │
 │                                                                 │
 └─────────────────────────────────────────────────────────────────┘
```

## Technical Summary

- **Framework(s):** PDFKit (`PDFView`, `PDFDocument`, `PDFPage`, `PDFOutline`, `PDFSelection`), SwiftUI (panel chrome, toolbar, sidebar toggles), AppKit via `NSViewRepresentable` (to host `PDFView` inside SwiftUI), Foundation
- **Key types:** <!-- all assumed — no source code exists yet -->
  - `PDFViewerPanel` — top-level SwiftUI view that assembles the toolbar, `PDFKitView`, and sidebar toggles
  - `PDFKitView` — `NSViewRepresentable` wrapping `PDFView` for hosting inside SwiftUI; handles `goBack:`, `goForward:`, `setScaleFactor:`, rotate, and selection callbacks
  - `PDFToolbarView` — SwiftUI toolbar with Prev/Next, page counter, zoom slider/buttons, rotate button, print/share, and sidebar toggle buttons
  - `TOCSidebarView` — SwiftUI outline list driven by `PDFOutline` tree from the document; tapping an item calls `PDFView.go(to:)`
  - `ThumbnailsSidebarView` — SwiftUI lazy-loading grid of `PDFPage.thumbnail(of:)` images; tapping navigates to that page
  - `PDFViewerViewModel` — `@Observable` object holding current page index, total page count, scale factor, rotation angle, sidebar visibility state, and a reference to the loaded `PDFDocument`
- **Threading model:**
  - `@MainActor` for all `PDFView` operations (rendering, navigation, selection) and `PDFViewerViewModel` mutations
  - Background `Task(priority: .utility)` for initial PDF loading and parsing of large documents, so the UI stays responsive during file open
  - Thumbnail generation offloaded to `Task(priority: .background)` with lazy rendering — only generate thumbnails for pages currently visible in the sidebar
- **Data flow:**
  1. File Tree selection or tab-switch triggers `InterPanelRouter.open(_:)` → Foundation passes the file URL to the PDF Viewer
  2. `PDFViewerViewModel` loads the URL via `PDFDocument(url:)` on a background `Task`
  3. `PDFKitView` observes the view model's `PDFDocument` reference and sets it on the wrapped `PDFView`
  4. User interactions (zoom, rotate, page navigation, sidebar toggles) update the view model, which calls `PDFView` methods accordingly
  5. Text selection is handled natively by `PDFView`; the user copies via ⌘C, which writes to `NSPasteboard` through PDFKit's built-in selection handling
  6. Print/Export delegates to `PDFView.printWithInfo(_:)` or `PDFDocument.dataRepresentation()` for Save As
- **State owned:**
  - `PDFViewerViewModel` — current `PDFDocument`, page index, total pages, scale factor, rotation, sidebar visibilities (TOC / Thumbnails)
  - Per-session scroll position and selection state are managed internally by `PDFView` and not duplicated in the view model
- **Dependencies:** Foundation module 2 (via `InterPanelRouter` for file-open routing, plus shared UI/UX primitives for toolbar icons and error banners); no dependency on modules 3, 4, 6, 7, or 8
- **Failure modes:**
  - Non-PDF file routed to PDF Viewer → `PDFDocument(url:)` returns `nil` → display error banner: "Cannot open — not a valid PDF file"
  - Corrupted PDF → `PDFDocument` initialises but has zero pages or throws on page access → catch and display "This PDF appears to be corrupted" with a retry button
  - Oversized PDF → enforce a configurable page-count or file-size limit (default: 10,000 pages or 500 MB) before loading; show warning with option to proceed
  - **Image display (ISS-048):** PNG/JPEG files are now openable via the PDF Viewer. `FileType` includes `.image` case for `png/jpg/jpeg` (ISS-048); `AppInterPanelRouter.open(_:)` routes `.image` files to module 5. `PDFViewerViewModel.loadImage(_:)` calls `PreviewImageResolver.nsImage(…)` to fetch a downsampled `NSImage` (2000 px max, 20 MB byte cap), wraps it with `PDFPage(image:)` into a single-page `PDFDocument`, and assigns to the document property. This reuses all existing fit/zoom/rotate/print controls with zero new view code. The 2000 px and 20 MB limits are enforced in the shared resolver (module 9.6) — same limit applies to Markdown and HTML (SR-1, SR-3). TOC and thumbnail sidebars are not visible for single-page image documents.
  - Missing file → `PDFDocument(url:)` returns `nil` → route back to Foundation's `.fileNotFound` error pathway
  - Thumbnail generation failure per-page → silently skip that thumbnail (single page failure does not block the grid)

## Sub-Modules

The PDF Viewer is a single monolithic panel and does not have formal sub-modules. The features listed below are implemented as views or components within the same module:

| Feature | Component | Responsibility |
|---|---|---|
| Fixed-Layout Rendering | `PDFKitView` + `PDFView` | Renders PDF pages at their native layout via PDFKit; supports continuous-scroll and single-page modes |
| Text Selection & Clipboard | `PDFView` (built-in) | Native PDFKit text selection; ⌘C copies to `NSPasteboard` as plain text and rich text |
| Interactive Elements | `PDFView` (built-in) | Handles hyperlinks, form fields, and annotations via PDFKit's built-in delegate methods |
| Scale and Orientation | `PDFViewerViewModel` + toolbar | Scale slider (25%–400%), fit-to-width toggle, and 90° clockwise rotation |
| Print and Save As | Toolbar action sheet | `PDFView.printWithInfo(_:)` for printing; `PDFDocument.dataRepresentation()` + `NSSavePanel` for Save As |
| Outline / TOC Sidebar | `TOCSidebarView` | Parses `PDFDocument.outlineRoot` into an indented `PDFOutline` tree; tapping jumps to the destination page |
| Thumbnails Sidebar | `ThumbnailsSidebarView` | Lazy-loaded grid of `PDFPage.thumbnail(of:size:)`; tapping jumps to page; grid auto-updates on document change |

## Spec Reference

> Extracted from `README.md` — the original bullet points for this module:

```
5. PDF VIEWER = the area where PDF content is rendered and displayed to the user.
  1. Fixed-Layout Rendering Engine
  2. Text Selection & Clipboard Copying
  3. Interactive Elements
  4. Scale and Orientation Control:
  5. Print and SaveAs function
  6. Outline & Table of Contents Sidebar 'aka another new panel = Sputnik' (parsing PDF bookmarks to jump directly to sections).
  7. Thumbnails Sidebar (visual grid navigation) 'aka another new panel = Sputnik'
```
