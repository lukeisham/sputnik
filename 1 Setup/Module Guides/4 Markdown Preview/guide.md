---
module: 4 Markdown Preview
status: active
last_updated: 2026-06-12
last_verified: 2026-06-12
plan: 1 Setup/Plans Completed/2026-06-08 4 Markdown Preview Implement Markdown Preview module.md
open_issues: ISS-061
---

## Purpose

The Markdown Preview renders the active editor tab's Markdown (or ASCII) content as a live, selectable styled document, synchronised in real time with the editor, so the user sees a formatted preview alongside their source text in the centre lower panel.

## Diagram

```
MARKDOWN PREVIEW PANEL  (occupies centre lower slot; see module 2.0 overview)
─────────────────────────────────────────────────────────────────────────────────

 ┌──────────────────────────────────────────────────────────────────────────────┐
 │  MARKDOWN PREVIEW — guide.md                                           [⋯]  │
 │  Toolbar: [↔ Fit Width]  [Aa]  [🔗]                                         │
 │  ─────────────────────────────────────────────────────────────────────────   │
 │                                                                              │
 │  # Sputnik Design Doc                                                        │
 │                                                                              │
 │  Sputnik is a **native macOS development environment** that coordinates      │
 │  six concurrent views within a unified, crash-resistant layout.              │
 │                                                                              │
 │  Some inline `code` and a [link to Foundation](2-Foundation.md).             │
 │                                                                              │
 └──────────────────────────────────────────────────────────────────────────────┘


 DATA FLOW
 ─────────

   Text Editor (mod 3)              AppState (mod 2.2)         Markdown Preview
   ──────────────────               ──────────────────         ────────────────

   user types in              activeDocument.text              MarkdownPreviewPanel
   .md / .ascii file ──────►  (observed via @Environment)  ──► .onChange triggers
                                                                   render()
                                                                      │
                                                             RenderThrottle (2.7)
                                                             throttles rapid calls
                                                                      │
                                                            buildNSAttributedString()
                                                            on background Task
                                                                      │
                                                       ┌──────────────┴────────────┐
                                                       │  images in Markdown?       │
                                                       │  local → NSTextAttachment  │
                                                       │  remote → labelled text    │
                                                       │  (via PreviewImageResolver │
                                                       │   in module 9)             │
                                                       └──────────────┬────────────┘
                                                                      │
                                                       parseMarkdownSegment()
                                                       AttributedString(markdown:)
                                                       → applyPresentationIntentStyling()
                                                         [PARTIAL — see ISS-060]
                                                                      │
                                                                      ▼
                                                           ┌──────────────────┐
                                                           │  NSTextView       │
                                                           │  (NSViewRep.)    │
                                                           │                  │
                                                           │  • selectable    │
                                                           │  • links tappable│
                                                           └──────────────────┘

  User interaction:
  ┌────────────────┐     ┌────────────────────┐     ┌────────────────┐
  │  Select text   │────►│ NSTextView built-in │────►│ ⌘C copies to   │
  │                │     │ selection handling  │     │ NSPasteboard   │
  ├────────────────┤     ├────────────────────┤     ├────────────────┤
  │  Click link    │────►│ NSTextViewDelegate  │────►│ InterPanelRouter│
  │                │     │ .clickedOnLink:     │     │ .open(url)     │
  │                │     │                     │     │ OR             │
  │                │     │                     │     │ NSWorkspace    │
  │                │     │                     │     │ .shared.open() │
  └────────────────┘     └────────────────────┘     └────────────────┘
```

## Source Files

| File | Responsibility |
|---|---|
| `MarkdownPreviewPanel.swift` | Top-level SwiftUI view; header bar, toolbar, content area; wires `MarkdownPreviewViewModel` and `MarkdownPreviewCoordinator`; owns render trigger via `.onChange` |
| `MarkdownPreviewViewModel.swift` | `@Observable @MainActor` class; owns `renderedString`, `fontScale`, `isRendering`, `renderError`; generation counter for stale-render guard; delegates rendering to `MarkdownPreviewRenderer` |
| `MarkdownPreviewRenderer.swift` | Rendering pipeline: `buildNSAttributedString`, `parseMarkdownSegment`, `resolveImageAttachment`, `applyPresentationIntentStyling`, `parseIntentKind`, `applyKindAttributes`, `SendableAttributedString` |
| `MarkdownPreview+ParsedIntentKind.swift` | `ParsedIntentKind` enum and `headingFontSizes` constant |
| `MarkdownRenderView.swift` | `NSViewRepresentable` wrapping `NSTextView`; receives coordinator externally; applies per-panel font and background (F-4) |
| `MarkdownPreviewCoordinator.swift` | `NSObject, NSTextViewDelegate @MainActor`; routes link clicks and injects right-click "More Context" menu items |

## Technical Summary

- **Framework(s):** SwiftUI (panel chrome, toolbar), AppKit via `NSViewRepresentable` (`NSTextView` for selectable rich text — justified under SW-3: SwiftUI `Text` does not support text selection), Foundation `AttributedString` with Markdown parsing, `NSTextViewDelegate` for link interactions
- **Key types:**
  - `MarkdownPreviewPanel` — top-level SwiftUI `View`; `@Environment(AppState.self)` + `@Environment(SettingsStore.self)`; creates `MarkdownPreviewCoordinator` in `@MainActor init` (stable across re-renders); holds `@State private var viewModel = MarkdownPreviewViewModel()`; triggers renders via `.onChange(of: appState.activeDocument?.text)` and `.onChange(of: appState.activeDocumentID)`
  - `MarkdownRenderView` — `NSViewRepresentable` wrapping `NSTextView`; receives the pre-created `MarkdownPreviewCoordinator` as an `init` parameter (`makeCoordinator()` returns the externally-provided instance, not a freshly created one); applies per-panel font/background from `SettingsStore` (F-4)
  - `MarkdownPreviewCoordinator` — `@MainActor NSObject, NSTextViewDelegate`; routes link clicks (`file://` → `InterPanelRouter`, `http/https/mailto` → `NSWorkspace`, unsafe schemes blocked); injects "More Context: Grammar Help" and "More Context: Markdown Help" into the right-click menu via `MoreContextMenu.items(...)` (2.7) when text is selected; holds `weak var router: (any InterPanelRouter)?`, `onRequestHelp` closure, `helpContextResolver`
  - `MarkdownPreviewViewModel` — `@Observable @MainActor` class; owns `renderedString: NSAttributedString`, `scrollOffset: CGFloat` (tracked, not yet wired to scroll view — ISS-061), `fontScale: CGFloat` (0.5–2.0), `isRendering: Bool`, `renderError: String?`; uses a monotonically-increasing `renderGeneration: UInt64` as a stale-render guard; delegates render throttling to `RenderThrottle` (Foundation 2.7)
  - `buildNSAttributedString(markdown:baseDir:)` — nonisolated file-scope async function; splits Markdown source around `![alt](path)` image references using `NSRegularExpression`; delegates text segments to `parseMarkdownSegment` and image references to `resolveImageAttachment`
  - `parseMarkdownSegment(_:)` — calls `AttributedString(markdown:options:)` with `.full` interpretedSyntax, then `applyPresentationIntentStyling`; falls back to plain text on parse error
  - `applyPresentationIntentStyling(_:)` — walks `AttributedString.runs` for `PresentationIntent` metadata, bridges to `NSMutableAttributedString`, calls `applyKindAttributes`; uses ObjC runtime `NSPresentationIntent` identity (via `perform(NSSelectorFromString("identity"))`) to extract the intent kind and header level (ISS-055: private API dependency; degrades to plain text on future OS changes without crashing)
  - `resolveImageAttachment(path:alt:baseDir:resolver:)` — remote `http(s)` refs render as `[label]` text (no network fetch); local refs resolved via `PreviewImageResolver` (module 9) and cached via `PreviewImageCache` (Foundation 2.7); result inserted as `NSTextAttachment`; oversized/missing files render as placeholder labels

- **Threading model:**
  - `@MainActor` for all `MarkdownPreviewViewModel` state mutations, `NSTextView` operations, and `MarkdownPreviewCoordinator` delegate callbacks
  - Render work runs via `RenderThrottle` (Foundation 2.7) on a background `Task(priority: .utility)` — prevents blocking the main thread on large documents
  - Generation counter (`renderGeneration`) guards against stale results: if `render()` is called again before the previous Task completes, the older result is discarded when it lands on the main actor
  - The panel observes `AppState` text changes via SwiftUI `.onChange` — no Combine publisher; `RenderThrottle` coalesces rapid calls

- **Data flow:**
  1. **Render trigger:** active `.markdown` or `.ascii` document text changes → `.onChange(of: appState.activeDocument?.text)` fires → `viewModel.render(markdown:fontScale:)` called
  2. **Throttle:** `RenderThrottle.throttle` coalesces rapid calls, running the work block after a typing pause
  3. **Parse (background Task):** `buildNSAttributedString(markdown:baseDir:)` splits source around image refs; text segments → `parseMarkdownSegment` → `AttributedString(markdown:)` + `applyPresentationIntentStyling`; image refs → `resolveImageAttachment`
  4. **Display:** `NSAttributedString` published back via `applyRenderedResult` on `@MainActor` (guarded by generation counter) → `MarkdownRenderView.updateNSView` sets it on `NSTextView.textStorage`
  5. **Text selection:** standard `NSTextView` selection; ⌘C copies to `NSPasteboard`
  6. **Link click:** `NSTextViewDelegate.textView(_:clickedOnLink:at:)` → `file://` → `InterPanelRouter.open(url)`; `http/https/mailto` → `NSWorkspace.shared.open`; `javascript/data/blob` → blocked and logged

- **State owned:**
  - `MarkdownPreviewViewModel` — `renderedString`, `fontScale`, `isRendering`, `renderError`, `scrollOffset` (tracked, not yet wired — ISS-061)
  - Active document text and identity are owned by Foundation `AppState` (2.2); the preview is a pure function of the active session and holds no document state (SR-1)

- **Dependencies:** Foundation 2.2 (`AppState.activeDocumentID`, `DocumentSession`, `AppState.requestedHelpTarget`); Foundation 2.1 (`InterPanelRouter.open(_:)`); Foundation 2.3 (`SettingsStore` — `resolvedMarkdownPreviewFont`, `markdownPreviewBackground` for F-4); Foundation 2.4 (UI primitives: `SputnikColor`, `SputnikSpacing`, `SputnikFont`); Foundation 2.7 (`RenderThrottle`, `PreviewImageCache`, `MoreContextMenu`, `HelpContextResolving`, `SputnikHelpContextResolver`); Module 9 (`PreviewImageResolver`). No dependency on modules 5, 6, 7, or 8.

- **Failure modes:**
  - Active document is not `.markdown` or `.ascii` → panel clears `renderedString` and shows placeholder: "Plain text file selected — open a Markdown file to preview" (or "ASCII file selected…" for `.ascii` type)
  - No active document → "No file open" empty-state placeholder
  - Markdown parse failure → `parseMarkdownSegment` catches the thrown error, returns plain text, sets `viewModel.renderError` → subtle yellow warning banner shown above the content; never a crash
  - `parseIntentKind` cannot extract `NSPresentationIntent` identity (future OS removes or changes the private ObjC SPI) → silently degrades to unstyled plain text; no crash
  - Local image reference (`![alt](path.png)`) → `PreviewImageResolver` resolves and downsamples (2000 px max, 20 MB cap); `PreviewImageCache` caches by URL; missing/oversized images render as `[label]` placeholder text
  - Remote `http(s)` image reference → rendered as `[label]` text, no network fetch
  - Link to local file that no longer exists → `InterPanelRouter.open(_:)` surfaces a `SputnikAlert` (2.4); preview unchanged
  - Unsafe link scheme (`javascript:`, `data:`, `blob:`) → `MarkdownPreviewCoordinator` blocks and logs; never opened
  - Very large document (10,000+ lines) → render runs on background Task via `RenderThrottle`; UI stays responsive; stale intermediate renders discarded by generation counter
  - Right-click with no text selected → `MoreContextMenu.items` returns `[]`; no "More Context" items injected; default context menu shown unchanged

## Invariants

- This panel **observes** `AppState` — the only write-back to Foundation is `AppState.requestedHelpTarget` (the help-request path, valid under SR-1 as the defined cross-module comms route)
- `MarkdownPreviewCoordinator` is created **once** in `MarkdownPreviewPanel.init` and held for the panel's lifetime — it is not recreated on re-render
- The panel renders both `.markdown` **and** `.ascii` file types; all other file types show the placeholder and clear any stale content
- All `NSTextView` access occurs on `@MainActor`; no `NSTextView` method is called from a background Task (SW-1)
- No document text is owned or duplicated by this module — the source of truth is `AppState.activeDocument.text` (SR-1)
- Network requests are never made — remote image references render as `[label]` text; only local files are resolved (SR-3 / security)
- `InterPanelRouter.open(_:)` is the only cross-module file-open path; this module never writes to `AppState.openDocuments` directly (SR-1)
- The generation counter in `MarkdownPreviewViewModel` must be incremented at the start of every `render()` call and checked before applying results — removing this guard causes visible flicker on fast typing

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
