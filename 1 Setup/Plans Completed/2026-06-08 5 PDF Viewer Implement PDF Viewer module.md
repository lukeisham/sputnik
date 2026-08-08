# Plan: Implement Module 5 — PDF Viewer

**Created:** 2026-06-08  
**Module:** 5 PDF Viewer  
**Build order position:** 6th (Foundation → Text Editor → Terminal → Project File Tree → Markdown Preview → **PDF Viewer** → HTML Preview → Resources)  
**Prerequisite modules completed:** Foundation (2), Text Editor (3), Terminal (7) ✅  
**Existing source:** None (directory empty)  

---

## Summary

Create 6 source files in `5 PDF viewer/` implementing a PDF rendering panel using PDFKit. The panel hosts a `PDFView` via `NSViewRepresentable`, provides a toolbar for page navigation, zoom, and rotation, and offers two toggleable sidebars — a Table of Contents tree parsed from `PDFOutline` and a lazy-loaded thumbnail grid. The module receives PDF files through `InterPanelRouter` events (or via `AppState.activeDocument` when a `.pdf` session becomes active) and loads them into `PDFDocument` on a background task.

---

## Pre-flight Checks

### Foundation APIs available (verified from source)

| Need | Available? | API |
|---|---|---|
| File-open routing | ✅ | `InterPanelRouter.open(_:)` + `events: AsyncStream<PanelEvent>` (`.fileOpened`) |
| Active document identity | ✅ | `AppState.activeDocumentID`, `AppState.activeDocument` |
| Error alerts | ✅ | `SputnikAlert.custom(title:message:)` |
| Design tokens | ✅ | `SputnikColor`, `SputnikSpacing`, `SputnikFont` |
| Panel layout slot | ⚠️ | `PanelPosition.centerLower` (see issue below) |

### Layout slot discrepancy — logged as ISS-007

`PanelLayout.default` assigns `.centerLower: .pdfViewer` and `.right: .markdownPreview`. However, the Module 4 guide says Markdown Preview occupies "centre lower" and the Module 5 guide says the PDF Viewer is "in Sputnik's right slot." The guides and the default layout disagree. This is **non-blocking** — panels are relocatable, so each module works regardless of slot. The layout can be corrected in `PanelLayout.default` after both modules are built, or the guides can be updated. Either way, the PDF Viewer code should not hard-code a slot assumption.

**Logged as ISS-007** (see `Issues.md` update in After Implementation).

### macOS APIs available

| Need | API |
|---|---|
| PDF rendering | `PDFView`, `PDFDocument`, `PDFPage`, `PDFSelection` (PDFKit) |
| TOC parsing | `PDFOutline` (PDFKit) |
| Thumbnail generation | `PDFPage.thumbnail(of:size:)` (PDFKit) |
| Printing | `PDFView.print(with:autoRotate:)` |
| Save As | `PDFDocument.dataRepresentation()` + `NSSavePanel` |
| Text selection | Built into `PDFView` — ⌘C copies to `NSPasteboard` |

---

## Files to Create

### 1. `5 PDF viewer/PDFViewerViewModel.swift`

**Responsibility:** `@Observable` `@MainActor` class — owns the loaded `PDFDocument` and all UI state (page, scale, rotation, sidebar visibility). Coordinates loading and error handling.

**Owned state:**
- `document: PDFDocument?` — the currently loaded document (`nil` when nothing is open)
- `currentPageIndex: Int` — zero-based index of the visible page
- `totalPageCount: Int` — derived from `document?.pageCount ?? 0`
- `scaleFactor: CGFloat` — zoom level (range 0.25…4.0, default 1.0)
- `isFitToWidth: Bool` — when true, auto-scales to fill the view width (default true)
- `rotation: Int` — cumulative rotation in degrees (0, 90, 180, 270)
- `isTOCVisible: Bool` — TOC sidebar toggle
- `isThumbnailsVisible: Bool` — thumbnails sidebar toggle
- `isLoading: Bool` — `true` while a `PDFDocument(url:)` call is in flight
- `errorMessage: String?` — non-nil when loading fails (invalid PDF, corrupted, missing file)
- `documentInfo: String` — computed: file size, page count, filename for the status bar

**Methods:**
- `func loadPDF(_ url: URL) async` — wraps `PDFDocument(url:)` in a `Task(priority: .utility)`; on success, publishes `document` on `@MainActor`; on nil (invalid/missing), sets `errorMessage`; validates page count and file size against configurable limits (default 10,000 pages / 500 MB), surfacing a warning
- `func navigateTo(page index: Int)` — bounds-checked; calls `PDFView.go(to:)` via the view binding
- `func navigateNext()`, `func navigatePrevious()` — page + 1 / page - 1 with wraparound option
- `func zoomIn()`, `func zoomOut()` — adjust `scaleFactor` by 0.25 increments within bounds
- `func toggleFitToWidth()` — switches between fit-to-width and the last manual scale factor
- `func rotateClockwise()` — adds 90° to `rotation`, wrapping at 360
- `func clearError()` — resets `errorMessage` to nil
- `func closeDocument()` — releases `document` (set to nil), resets all state to defaults

**Threading (MR-3, SW-1):**
- `loadPDF(url:)` dispatches `PDFDocument(url:)` to `Task(priority: .utility)` — `PDFDocument` initialisation parses the file header and builds the page catalogue, which can be slow for large files
- Result published on `@MainActor`
- Page count/file-size guard runs synchronously on the main thread (trivial check after load)

**Dependency injection:**
- Receives an `InterPanelRouter` reference or subscribes to its `events` stream to detect `.fileOpened(url, .pdf)` events
- Alternatively, driven by `AppState.activeDocument` — when the active session's `fileType == .pdf`, load its URL. This aligns with the existing preview panel pattern (modules 4, 8).

**Load guard (failure mode — oversized PDF):**
```swift
private let maxPages = 10_000
private let maxFileSize: Int64 = 500 * 1_024 * 1_024  // 500 MB

// After loading document, before publishing:
guard document.pageCount <= maxPages else {
    document = nil
    errorMessage = "This PDF has \(document.pageCount) pages (limit: \(maxPages))."
    return
}
```

---

### 2. `5 PDF viewer/PDFKitView.swift`

**Responsibility:** `NSViewRepresentable` wrapping `PDFView`. Bridges PDFKit's AppKit view into SwiftUI. Handles display mode, scale, rotation, and scroll-position coordination with the ViewModel.

**AppKit bridge rationale (SW-3):** `PDFView` is an AppKit view with no SwiftUI equivalent. `NSViewRepresentable` is the correct interop path.

**`makeNSView`:**
- Create `PDFView` with zero frame
- Configure:
  - `displayMode = .singlePageContinuous` (scrollable vertical layout)
  - `displayDirection = .vertical`
  - `autoScales = true` (fit-to-width by default, maps to `viewModel.isFitToWidth`)
  - `displaysPageBreaks = true`
  - `backgroundColor = NSColor(SputnikColor.secondaryBackground)`
  - Enable built-in text selection (default on for `PDFView`)
- Assign `delegate` = context.coordinator (for page-change callbacks)

**`updateNSView`:**
- Apply `viewModel.document` → `pdfView.document = viewModel.document`
- Apply `viewModel.scaleFactor` → `pdfView.scaleFactor = viewModel.scaleFactor` (only when `!isFitToWidth`)
- Apply `viewModel.rotation` → set `pdfView.rotation` (triggers re-layout)
- Navigate to page if `viewModel.currentPageIndex` differs from current visible page
- Sync `pdfView.autoScales = viewModel.isFitToWidth`

**Coordinator** (inner class of `PDFKitView` or separate file — scope is small, so inline is fine per SR-6):
- Conforms to `PDFViewDelegate`
- `pdfViewPageChanged(_:)` → updates `viewModel.currentPageIndex` from `pdfView.currentPage`
- `pdfViewWillChangeScaleFactor(_:)` → syncs manual zoom changes back to `viewModel.scaleFactor`

**PDF selection + clipboard:** `PDFView` handles text selection natively. The user selects text with the mouse, ⌘C triggers `NSPasteboard.general` copy through PDFKit's built-in `PDFSelection` handling. No custom code needed.

---

### 3. `5 PDF viewer/PDFToolbarView.swift`

**Responsibility:** SwiftUI toolbar view with page navigation, zoom, rotation, and sidebar toggles.

**Layout (matching guide's diagram):**
```
[◀ Prev]  [Page 3 / 24]  [Next ▶]   [🔍−  100%  🔍+]  [↻]  [☰ TOC]  [⊞ Thumb]
```

**Controls:**
- **Prev `[◀]`:** Calls `viewModel.navigatePrevious()`. Disabled when `currentPageIndex == 0`.
- **Page indicator `[Page 3 / 24]`:** Non-editable label; tapping could reveal a "Go to Page…" sheet (optional enhancement).
- **Next `[▶]`:** Calls `viewModel.navigateNext()`. Disabled when `currentPageIndex == totalPageCount - 1`.
- **Zoom out `[🔍−]`:** Calls `viewModel.zoomOut()`. Disabled when at min scale.
- **Scale label `[100%]`:** Shows current zoom as percentage. Tapping cycles fit-to-width on/off.
- **Zoom in `[🔍+]`:** Calls `viewModel.zoomIn()`. Disabled when at max scale.
- **Rotate `[↻]`:** Calls `viewModel.rotateClockwise()`.
- **TOC toggle `[☰]`:** Toggles `viewModel.isTOCVisible`. Highlighted when active.
- **Thumbnails toggle `[⊞]`:** Toggles `viewModel.isThumbnailsVisible`. Highlighted when active.

**Additional toolbar items (overflow menu or right-side):**
- Print → `pdfView.print(with: pdfView.document, autoRotate: true)`
- Save As → `NSSavePanel` + `pdfView.document.dataRepresentation()` → writes to chosen path
- Share → `NSSharingServicePicker` with the PDF data

**Styling:** Uses `SputnikColor`, `SputnikSpacing.sm` for button spacing, `SputnikFont.caption` for labels. Toolbar sits in a `HStack` with `Divider` separators between groups.

---

### 4. `5 PDF viewer/TOCSidebarView.swift`

**Responsibility:** SwiftUI outline list rendering the PDF's table of contents from `PDFOutline`.

**Data source:** `pdfDocument.outlineRoot` — a root `PDFOutline` node whose children are the top-level TOC entries. Each `PDFOutline` node has:
- `.label: String?` — the section title
- `.destination: PDFDestination?` — the page + position to jump to
- `.numberOfChildren: Int` + `.child(at:)` — for nested entries

**Rendering:**
- Use SwiftUI `List` with recursive `OutlineGroup` or manual `DisclosureGroup` nesting
- Each row: indent based on depth, label text, optional page number
- Tapping a row calls `pdfView.go(to: outline.destination)` via the ViewModel
- Empty state when `document?.outlineRoot == nil`: "No table of contents available"

**Threading:** `PDFOutline` tree is already loaded when `PDFDocument` is initialised — no additional parsing needed. Tree traversal is on `@MainActor` since it's view-layer work.

**Lazy disclosure:** Nested children are accessed on demand (when user expands a disclosure group) — no recursive pre-expansion of the entire tree.

---

### 5. `5 PDF viewer/ThumbnailsSidebarView.swift`

**Responsibility:** SwiftUI lazy-loading grid of page thumbnails for visual navigation.

**Data source:** `pdfDocument.pageCount` — iterate pages `0..<totalPageCount`. Each `PDFPage` accessed via `pdfDocument.page(at:)`.

**Rendering:**
- `LazyVGrid` with 2 columns (or adjustable via sidebar width)
- Each cell: `PDFPage.thumbnail(of:size:)` rendered as an `Image` (via `NSImage` → SwiftUI `Image`)
- Current page highlighted with an accent border (`SputnikColor.accent`)
- Page number label below each thumbnail
- Tapping a cell calls `viewModel.navigateTo(page:)`

**Thumbnail loading:**
- Generate on `Task(priority: .background)` with lazy rendering — only create thumbnails for cells currently visible in the grid
- Cache generated thumbnails in a `[Int: Image]` dictionary on the ViewModel to avoid re-generating on scroll
- On document change, clear the cache
- On thumbnail generation failure (per-page), skip that cell silently — show a placeholder icon

**Thumbnail size:** Target `CGSize(width: 120, height: 160)` — scaled to fit while preserving the page's aspect ratio.

**Empty state:** "No thumbnails" when `totalPageCount == 0`.

---

### 6. `5 PDF viewer/PDFViewerPanel.swift`

**Responsibility:** Top-level SwiftUI view — assembles `PDFToolbarView`, `PDFKitView`, and the two sidebar views. The single entry point wired into the app's layout system.

**Layout:**
```
┌──────────────────────────────────────────────────────────────┐
│  PDFToolbarView                                               │
├──────────────────────────────────┬───────────────────────────┤
│  (optional TOC sidebar)          │  PDFKitView                │
│  (optional Thumbnails sidebar)   │  (PDFView via NSViewRep)   │
│                                  │                            │
└──────────────────────────────────┴───────────────────────────┘
└── optional Status Bar ───────────────────────────────────────┘
```

**Sub-components:**
- **Loading state:** `viewModel.isLoading == true` → centered `ProgressView()` with "Loading PDF…"
- **Error state:** `viewModel.errorMessage != nil` → error banner with `viewModel.errorMessage` + "Try Again" button (calls `viewModel.loadPDF(url)` again)
- **Empty state:** `viewModel.document == nil && !isLoading && errorMessage == nil` → "Open a PDF file to view" with an optional "Open…" button (triggers `NSOpenPanel` filtered to `.pdf` UTIs)
- **Active state:** Toolbar + sidebars + `PDFKitView`

**Sidebar layout:** 
- `isTOCVisible` → `TOCSidebarView` slides in from the left side of the panel content (or replaces the PDF view, depending on available width)
- `isThumbnailsVisible` → `ThumbnailsSidebarView` (can be shown alongside TOC)
- Both hidden → full `PDFKitView` width
- Layout uses `HStack` with conditional views

**Status bar (optional, toggled from View menu):**
- Shows: `"Page \(currentPageIndex + 1) of \(totalPageCount) | File: \(filename) | \(fileSize) | \(scaleFactor)%"`
- Communicates through `AppState.layout` for the toggle state, or uses a local `@State` + `@AppStorage`

**Dependencies:**
```swift
@Environment(AppState.self) private var appState
@State private var viewModel = PDFViewerViewModel()
```
Receives `router: (any InterPanelRouter)?` at init for file-open routing.

**Trigger for loading:** Observes `appState.activeDocument`. When it changes to a `.pdf` session whose URL differs from the currently loaded document, calls `viewModel.loadPDF(url)`.

---

## Implementation Order

1. **`PDFViewerViewModel.swift`** — pure logic and state; testable in isolation
2. **`PDFKitView.swift`** — NSViewRepresentable bridge; depends on ViewModel
3. **`PDFToolbarView.swift`** — toolbar UI; depends on ViewModel
4. **`TOCSidebarView.swift`** — TOC list; depends on `PDFOutline` + ViewModel
5. **`ThumbnailsSidebarView.swift`** — thumbnail grid; depends on `PDFPage` + ViewModel
6. **`PDFViewerPanel.swift`** — final assembly; depends on all above

---

## Integration Points

| Point | Foundation API | Usage |
|---|---|---|
| File-open detection | `AppState.activeDocument` | When `.fileType == .pdf`, load its URL |
| Error alerts | `SputnikAlert.custom(title:message:)` | Invalid PDF, corrupted, missing file |
| File-open routing back | `InterPanelRouter.open(_:)` | TOC entries that reference other PDFs |
| Reveal in Finder | `NSWorkspace.shared.activateFileViewerSelecting([url])` | Overflow menu action |
| Print | `PDFView.print(with:autoRotate:)` | Toolbar print action |
| Save As | `NSSavePanel` + `PDFDocument.dataRepresentation()` | Toolbar save action |
| Styling | `SputnikColor`, `SputnikSpacing`, `SputnikFont` | Toolbar, sidebars, status bar |
| Layout slot | `PanelPosition.centerLower` (per `PanelLayout.default`) | Wired by the App Overview |

---

## Coding Rule Compliance Checklist

- [ ] **SR-1:** Only communicates through Foundation (`AppState`, `InterPanelRouter`, design tokens); owns its own `PDFDocument` (legitimate — PDFs are loaded independently, not backed by editor text)
- [ ] **SR-2:** No force-unwraps; `PDFDocument(url:)` returns optional → handled; `page(at:)` bounds-checked; `thumbnail(of:)` failure caught; all error paths have user-facing messages
- [ ] **SR-3:** `PDFDocument` is loaded once and shared with `PDFView` (zero-copy); thumbnails are lazily generated and cached with a bounded dictionary; sidebar trees are traversed on demand
- [ ] **SR-4:** PDF loading on `Task(priority: .utility)`; thumbnail generation on `Task(priority: .background)`; `@MainActor` for all view/PDFView mutations
- [ ] **SR-5:** Uses PDFKit exclusively (`PDFView`, `PDFDocument`, `PDFPage`, `PDFOutline`, `PDFSelection`); `NSSavePanel`, `NSWorkspace` — all Apple frameworks. No third-party PDF libraries.
- [ ] **SR-6:** One responsibility per file — 6 files as listed above
- [ ] **SW-1:** `async/await`, `Task` for loading and thumbnails; `@MainActor` on ViewModel and views
- [ ] **SW-2:** `[weak self]` in any escaping closures (PDFView delegate callbacks, thumbnail Tasks); audit for cycles between `PDFView` ↔ delegate ↔ ViewModel
- [ ] **SW-3:** `NSViewRepresentable` for `PDFView` — justified: PDFKit has no SwiftUI equivalent
- [ ] **SW-4:** Doc comments on all public types/methods following triple-slash convention
- [ ] **MR-1:** PDFKit for all PDF work — rendering, selection, outline, thumbnails
- [ ] **MR-3:** `.utility` for PDF loading, `.background` for thumbnails

---

## Layout Slot Discrepancy — ISS-007

`PanelLayout.default` assigns `.centerLower: .pdfViewer` and `.right: .markdownPreview`. The Module 4 guide says Markdown Preview is "centre lower" and the Module 5 guide says PDF Viewer is "in the right slot." These conflict.

**Resolution path:** Log as ISS-007. After both modules are implemented, either:
- Option A: Update `PanelLayout.default` to swap the assignments (`.right: .pdfViewer`, `.centerLower: .markdownPreview`) to match the guides.
- Option B: Update the guides to match the existing layout.

Neither option blocks implementation — modules are slot-agnostic.

---

## After Implementation

1. Verify the module compiles cleanly
2. Verify integration into the main layout at `PanelPosition.centerLower`
3. Manual smoke tests:
   - Open a `.pdf` file → PDF renders in `PDFView` with toolbar
   - Page navigation (Prev/Next) → page changes, counter updates
   - Zoom in/out → scale adjusts; scale label shows percentage
   - Fit-to-width toggle → auto-scales to fill width
   - Rotate → pages rotate 90° clockwise
   - Text selection → highlight text, ⌘C → paste into TextEdit (plain + rich)
   - TOC sidebar → shows outline tree, tap entry → jumps to page
   - Thumbnails sidebar → shows lazy grid, tap thumbnail → jumps to page
   - Print → system print dialog
   - Save As → `NSSavePanel`, writes PDF
   - Open a corrupted/invalid PDF → error banner with message
   - Close document → returns to empty state
   - Switch from a `.md` tab to a `.pdf` tab → PDF Viewer loads the PDF automatically
4. Log ISS-007 in `References/Issues.md`
5. Update the Module Guide: `status: draft` → `status: complete`, update `last_updated`
6. Move this plan to `Plans Completed/`
