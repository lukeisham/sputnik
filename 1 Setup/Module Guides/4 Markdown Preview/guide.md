---
module: 4 Markdown Preview
status: complete
last_updated: 2026-06-10
plan: 1 Setup/Plans New/2026-06-08 4 Markdown Preview Implement Markdown Preview module.md
---

## Purpose

The Markdown Preview renders the active editor tab's Markdown content as a live, selectable styled document, synchronised in real time with the editor, so the user sees a formatted preview alongside their source text in the centre lower panel.

## Diagram

```
MARKDOWN PREVIEW PANEL  (occupies centre lower slot; see module 2.0 overview)
─────────────────────────────────────────────────────────────────────────────────

 ┌──────────────────────────────────────────────────────────────────────────────┐
 │  MARKDOWN PREVIEW — guide.md                                           [⋯]  │
 │  Toolbar: [🔍 Fit Width]  [Aa]  [🔗]                                        │
 │  ─────────────────────────────────────────────────────────────────────────    │
 │                                                                               │
 │  # Sputnik Design Doc                                                         │
 │  ════════════════════                                                         │
 │                                                                               │
 │  Sputnik is a **native macOS development environment** that coordinates       │
 │  six concurrent views within a unified, crash-resistant layout.               │
 │                                                                               │
 │                                                                               │
 │  ## Architecture                                                              │
 │  ─────────────────                                                            │
 │                                                                               │
 │  The app is organised into 8 modules, each with a single responsibility:      │
 │                                                                               │
 │  | Module | Name           | Purpose                              |          │
 │  |--------|----------------|--------------------------------------|          │
 │  | 2      | Foundation     | Inter-panel comms, state, settings  |          │
 │  | 3      | Text Editor    | Text/Markdown/HTML editing          |          │
 │  | 4      | Markdown Prev. | Live-rendered Markdown preview      |◀── you    │
 │  | 5      | PDF Viewer     | PDFKit rendering, TOC sidebar       |  are      │
 │  | …      | …              | …                                    |  here     │
 │                                                                               │
 │  > **Note:** The build order is defined in readme.md.                         │
 │                                                                               │
 │  Some inline `code` and a [link to Foundation](2-Foundation.md).              │
 │                                                                               │
 │  ---                                                                          │
 │                                                                               │
 │  ## Features Checklist                                                       │
 │                                                                               │
 │  ☑ Live synchronisation with editor                                           │
 │  ☐ Text selection and clipboard copy                                          │
 │  ☑ Clickable links                                                            │
 │                                                                               │
 └──────────────────────────────────────────────────────────────────────────────┘


 DATA FLOW
 ─────────

   Text Editor (mod 3)                  Foundation                    Markdown Preview
   ──────────────────                   ──────────                    ────────────────

   user types in                    AppState                          MarkdownPreview
   .md file                         activeDocument──►  PrepView
                        ──────►     .text (debounced)       │
                                                             │ observes active session
                                                             │
                                                    ┌───────┴──────────┐
                                                    │  is .markdown?   │
                                                    │  yes → render    │
                                                    │  no  → placeholder
                                                    └──────────────────┘
                                                             │
                                                   convert Markdown
                                                   to AttributedString
                                                   via AttributedString
                                                   .init(markdown:)
                                                             │
                                                             ▼
                                                    ┌──────────────────┐
                                                    │  NSTextView      │
                                                    │  (NSViewRep.)    │
                                                    │                  │
                                                    │  • selectable    │
                                                    │  • links tappable│
                                                    │  • scroll sync   │
                                                    └──────────────────┘

  User interaction:
  ┌────────────────┐     ┌────────────────────┐     ┌────────────────┐
  │  Select text   │────►│ NSTextView built-in │────►│ ⌘C copies to   │
  │                │     │ selection handling  │     │ NSPasteboard   │
  ├────────────────┤     ├────────────────────┤     ├────────────────┤
  │  Click link    │────►│ NSTextViewDelegate  │────►│ InterPanelRouter│
  │                │     │ .click(on: URL)     │     │ .open(url)     │
  │                │     │                     │     │ OR             │
  │                │     │                     │     │ NSWorkspace    │
  │                │     │                     │     │ .shared.open() │
  └────────────────┘     └────────────────────┘     └────────────────┘
```

## Technical Summary

- **Framework(s):** SwiftUI (panel chrome, toolbar), AppKit via `NSViewRepresentable` (to host `NSTextView` for selectable rich text — justified under SW-3 since SwiftUI's `Text` does not support text selection), Foundation `AttributedString` with Markdown parsing, `NSTextViewDelegate` for link interactions
- **Key types:** <!-- all assumed — no source code exists yet -->
  - `MarkdownPreviewPanel` — top-level SwiftUI view that assembles the toolbar and the `MarkdownRenderView`; observes `AppState.activeDocument` and triggers re-render when the active session's text changes
  - `MarkdownRenderView` — `NSViewRepresentable` wrapping an `NSTextView`; receives the parsed `AttributedString` and applies it to the text view's `textStorage`; configures the text view for read-only, selectable, link-interactive display
  - `MarkdownPreviewCoordinator` — the `NSViewRepresentable.Coordinator`; conforms to `NSTextViewDelegate` and handles link clicks (`.clickOnLink:`) — routing local file URLs through `InterPanelRouter.open(_:)` and external URLs through `NSWorkspace.shared.open(_:)`; also conforms to `NSTextViewDelegate.textView(_:menu:at:for:)` to inject "More Context: Grammar Help" and "More Context: Markdown Help" items into the right-click context menu via the shared `MoreContextMenu.items(...)` builder (2.7)
  - `MarkdownPreviewViewModel` — `@Observable` class; holds the rendered `AttributedString`, scroll position, font size/zoom preference, and a reference to the active session's debounced text publisher; runs Markdown-to-AttributedString conversion on a background `Task` for large documents
- **Threading model:**
  - `@MainActor` for all `NSTextView` operations (setting `textStorage`, scroll position, selection updates) and `MarkdownPreviewViewModel` mutations
  - Background `Task(priority: .utility)` for the Markdown-to-`AttributedString` conversion — for large documents this parsing can be non-trivial; the resulting `AttributedString` (which is `Sendable`) is published back on `@MainActor`
  - Re-render is triggered by observing `activeDocumentID` and the active session's debounced `.text` publisher (the debounce lives in Text Editor 3, not here) — prevents re-parsing on every keystroke
  - **F-4 (Per-panel font/background):** `MarkdownRenderView` reads `settings.resolvedMarkdownPreviewFont` as the base `NSFont` and `settings.markdownPreviewBackground` as the `NSTextView.backgroundColor`; resolved font falls back to `editorFont` when no per-panel override is set.
- **Data flow:**
  1. **Render trigger:** Text Editor modifies active `.markdown` document → debounced text update via `AppState.activeDocument.text` publisher → `MarkdownPreviewViewModel` detects change
  2. **Parse:** Text is passed to `AttributedString(markdown:)` on a background `Task(priority: .utility)` — this produces a styled `AttributedString` with headings, bold, italic, code, links, tables, lists, and block quotes rendered using system font styles
  3. **Display:** Parsed `AttributedString` is set on `MarkdownRenderView`'s `NSTextView.textStorage` on `@MainActor`; the text view renders it read-only with natural text wrapping, preserving the editor's scroll position across updates where possible
  4. **Text selection:** User drags to select text in `NSTextView` — standard AppKit selection behaviour; ⌘C copies rich text and plain text to `NSPasteboard`
  5. **Link click:** `NSTextViewDelegate.textView(_:clickOnLink:atIndex:)` — classifies the URL via a policy similar to `LinkNavigationPolicy` (module 8): local `file://` URLs → `InterPanelRouter.open(url)` → new editor tab; external `http(s)` URLs → `NSWorkspace.shared.open(url)` → default browser
- **State owned:**
  - `MarkdownPreviewViewModel` — rendered `AttributedString`, scroll offset, font scale preference
  - The active document text and identity are owned by Foundation `AppState` (2.2) — the preview is a pure function of the active session and holds no document state of its own (SR-1, SR-3)
- **Dependencies:** Foundation 2.2 (`AppState.activeDocumentID`, `DocumentSession`), Foundation 2.1 (`InterPanelRouter.open(_:)`), Foundation 2.4 (UI/UX primitives for toolbar styling, placeholder styling, and error banners), Foundation 2.7 (`MoreContextMenu`, `HelpContextResolving`, `HelpContextQuery`), Text Editor 3 (source of `.markdown` text with debounced publishing); no dependency on modules 5, 6, 7, or 8
- **Failure modes:**
  - Active document is not `.markdown` → panel shows a neutral placeholder ("No Markdown file open"); it does **not** render stale content from a previously active tab
  - Right-click More Context with no selection → `MoreContextMenu` returns `[]`, no menu items are added; the default context menu is shown unchanged
  - `NSTextViewDelegate.textView(_:menu:at:for:)` replaces the menu (by returning a new one), not mutating the passed-in menu — ensures the NSTextView doesn't add duplicate items
  - Markdown parse failure (invalid syntax that `AttributedString(markdown:)` cannot handle) → catch the thrown error; render as plain text with a subtle warning banner, never a crash
  - **Image display (ISS-046):** Local image references (`![alt](path.png)`) are post-processed after Markdown parsing: for each relative/local path, `PreviewImageResolver.nsImage(relativeTo:baseDir)` decodes and downsamples via ImageIO (2000 px max, 20 MB byte cap). On success, an `NSTextAttachment` splices the downsampled `NSImage` into the `NSAttributedString` at the reference position, preserving text selection/copy around it. Remote `http(s)` image URLs render as labelled links (no network fetch). Missing/corrupt/oversized images show a placeholder cell. The 2000 px and 20 MB limits are enforced in the shared resolver (module 9.6) — same limit applies to HTML and PDF image loading (SR-1, SR-3).
  - Link target is a local file that no longer exists → `InterPanelRouter.open(_:)` classifies it and surfaces a `SputnikAlert` (2.4); the preview is left unchanged
  - Very large Markdown document (10,000+ lines) → conversion runs on background `Task(priority: .utility)`; the UI remains responsive during parsing; intermediate renders are skipped if a newer text arrives before parsing completes
  - External link with unexpected scheme (`javascript:`, `data:`, …) → blocked and logged, never opened

## Spec Reference

> Extracted from `README.md` — the original bullet points for this module:

```
4. MARKDOWN VIEWER = the area where Markdown content is rendered and displayed to the user.
  1. Live Synchronization with Editor Window
  2. Text Selection & Clipboard Copying
  3. Interactive Elements
```

> Module map entry (from `CLAUDE.md`):

```
| 4 | Markdown Preview | Live-rendered Markdown preview, synced to editor |
```

> Build order note:

```
Foundation → Text Editor Window → Terminal → Project File Tree → Markdown Preview → PDF Viewer → HTML Preview → Resources
```
