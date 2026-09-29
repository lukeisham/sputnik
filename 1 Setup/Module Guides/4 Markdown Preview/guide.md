---
module: 4 Markdown Preview
status: stable
last_updated: 2026-09-28
last_verified: 2026-06-15
open_issues: none
plan: 1 Setup/Plans Completed/2026-06-08 4 Markdown Preview Implement Markdown Preview module.md
---

## Purpose

The Markdown Preview renders the active editor tab's Markdown (or ASCII) content as a live, selectable styled document, synchronised in real time with the editor, so the user sees a formatted preview alongside their source text in a resizable vertical column.

## Diagram

```
MARKDOWN PREVIEW PANEL  (occupies a resizable vertical column; toggled via toolbar)
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
                                                         (styled — ISS-060 resolved)
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
| `MarkdownPreviewPanel.swift` | Top-level SwiftUI view; header bar, toolbar (Fit Width, Font Size, Links, Scroll Sync, ⌘-Click Nav, large-file indicator), content area; wires `MarkdownPreviewViewModel` and `MarkdownPreviewCoordinator`; owns render trigger via `.onChange`; passes `syncScrollFraction` to `MarkdownRenderView` |
| `MarkdownPreviewViewModel.swift` | `@Observable @MainActor` class; owns `renderedString`, `fontScale`, `isRendering`, `renderError`, `isLargeFile`, `sourceMap`; adaptive delay + block cache; generation counter for stale-render guard |
| `MarkdownPreviewRenderer.swift` | Rendering pipeline: `buildBlockCachedAttributedString`, `buildNSAttributedString`, `parseMarkdownSegment`, `resolveImageAttachment`, `applyPresentationIntentStyling`, `parseIntentKind`, `applyKindAttributes`, `MarkdownBlock`, `MarkdownSourceBlock`, `splitMarkdownBlocks`, `SendableAttributedString` |
| `MarkdownPreview+ParsedIntentKind.swift` | `ParsedIntentKind` enum and `headingFontSizes` constant |
| `MarkdownRenderView.swift` | `NSViewRepresentable` whose `NSViewType` is an `NSScrollView` the bridge **owns** (ISS-096), wrapping an `NSTextView`; receives coordinator externally; applies per-panel font/background (F-4); applies `syncScrollFraction` for editor→preview scroll sync; installs ⌘-click gesture recognizer; wires the print / save-as-PDF / save-as-Markdown actions once in `makeNSView` onto the coordinator (ISS-095); `dismantleNSView` removes the scroll observer (ISS-093) |
| `MarkdownPreviewCoordinator.swift` | `NSObject, NSTextViewDelegate @MainActor`; routes link clicks; injects right-click "More Context" menu items; `handleCommandClick` for ⌘-click source navigation; holds `lastSyncScrollFraction`, `bidirectionalEnabled`, `weak viewModel` |

## Technical Summary

- **Framework(s):** SwiftUI (panel chrome, toolbar), AppKit via `NSViewRepresentable` (`NSTextView` for selectable rich text — justified under SW-3: SwiftUI `Text` does not support text selection), Foundation `AttributedString` with Markdown parsing, `NSTextViewDelegate` for link interactions
- **Key types:**
  - `MarkdownPreviewPanel` — top-level SwiftUI `View`; `@Environment(AppState.self)` + `@Environment(SettingsStore.self)`; creates `MarkdownPreviewCoordinator` in `@MainActor init` (stable across re-renders); holds `@State private var viewModel = MarkdownPreviewViewModel()`; triggers renders via `.onChange(of: appState.activeDocument?.text)` and `.onChange(of: appState.activeDocumentID)`
  - `MarkdownRenderView` — `NSViewRepresentable` wrapping `NSTextView`; receives the pre-created `MarkdownPreviewCoordinator` as an `init` parameter (`makeCoordinator()` returns the externally-provided instance, not a freshly created one); applies per-panel font/background from `SettingsStore` (F-4)
  - `MarkdownPreviewCoordinator` — `@MainActor NSObject, NSTextViewDelegate`; routes link clicks (`file://` → `InterPanelRouter`, `http/https/mailto` → `NSWorkspace`, unsafe schemes blocked); injects "More Context: Style Guide" and "More Context: Markdown Help" into the right-click menu via `MoreContextMenu.items(...)` (2.7) when text is selected; holds `weak var router: (any InterPanelRouter)?`, `onRequestHelp` closure, `helpContextResolver`
  - `MarkdownPreviewViewModel` — `@Observable @MainActor` class; owns `renderedString: NSAttributedString`, `scrollOffset: CGFloat` (wired — ISS-061 resolved), `fontScale: CGFloat` (0.5–2.0), `isRendering: Bool`, `renderError: String?`, `isLargeFile: Bool` (true when `text.utf16.count >= 80_000`), `sourceMap: [MarkdownSourceBlock]` (built by each render, used for ⌘-click navigation); `blockCache: [Int: (text: String, rendered: SendableAttributedString)]` (per-block hash cache storing source text for collision detection; half-evicts oldest entries when count exceeds 500 — ISS-091); `adaptiveDelay(for:)` returns 0.05/0.10/0.20/0.30 s based on document size; uses a monotonically-increasing `renderGeneration: UInt64` as a stale-render guard; delegates render throttling to `RenderThrottle` (Foundation 2.7); `cancel()` invalidates any pending render and clears `isRendering` — called by the panel before clearing `renderedString` on document close or type switch (ISS-089)
  - `MarkdownSourceBlock` — public `Sendable` struct; `sourceStartLine`, `sourceEndLine` (0-based), `renderedLocation`, `renderedLength` in the output `NSAttributedString`; `contains(renderedOffset:)` helper for fast lookup; built by `buildBlockCachedAttributedString` and stored on `viewModel.sourceMap`
  - `splitMarkdownBlocks(_:)` — splits raw Markdown on blank lines into `[MarkdownBlock]`; tracks fenced code blocks (```` ``` ```` / `~~~`) to avoid splitting inside them; assigns `startLine`/`endLine` per block
  - `buildBlockCachedAttributedString(markdown:baseDir:cache:)` — assembles the full output by rendering each block; text-only blocks hit the hash cache with a collision guard (`cached.text == block.text`); image blocks always re-render; returns `(NSAttributedString, [MarkdownSourceBlock], [Int: (text: String, rendered: SendableAttributedString)])` — the caller merges new cache entries on the main actor (ISS-091)
  - `buildNSAttributedString(markdown:baseDir:)` — used for blocks with images; splits Markdown source around `![alt](path)` image references using `NSRegularExpression`; delegates text segments to `parseMarkdownSegment` and image references to `resolveImageAttachment`
  - `parseMarkdownSegment(_:)` — calls `AttributedString(markdown:options:)` with `.full` interpretedSyntax, then `applyPresentationIntentStyling`; falls back to plain text on parse error
  - `applyPresentationIntentStyling(_:)` — walks `AttributedString.runs` for `PresentationIntent` metadata, bridges to `NSMutableAttributedString`, calls `applyKindAttributes`; uses ObjC runtime `NSPresentationIntent` identity (via `perform(NSSelectorFromString("identity"))`) to extract the intent kind and header level (ISS-055: private API dependency; degrades to plain text on future OS changes without crashing)
  - `resolveImageAttachment(path:alt:baseDir:resolver:)` — remote `http(s)` refs render as `[label]` text (no network fetch); local refs resolved via `PreviewImageResolver` (module 9) and cached via `PreviewImageCache` (Foundation 2.7); result inserted as `NSTextAttachment`; oversized/missing files render as placeholder labels

- **Threading model:**
  - `@MainActor` for all `MarkdownPreviewViewModel` state mutations, `NSTextView` operations, and `MarkdownPreviewCoordinator` delegate callbacks
  - Render work runs via `RenderThrottle` (Foundation 2.7) on a background `Task(priority: .utility)` — prevents blocking the main thread on large documents
  - Generation counter (`renderGeneration`) guards against stale results: if `render()` is called again before the previous Task completes, the older result is discarded when it lands on the main actor
  - The panel observes `AppState` text changes via SwiftUI `.onChange` — no Combine publisher; `RenderThrottle` coalesces rapid calls

- **Data flow:**
  1. **Render trigger:** active `.markdown` or `.ascii` document text changes → `.onChange(of: appState.activeDocument?.text)` fires → `viewModel.render(markdown:baseDir:)` called with `baseDir` derived from the active document URL
  2. **Throttle:** `RenderThrottle.throttle` coalesces rapid calls, running the work block after a typing pause
  3. **Parse (background Task):** `buildNSAttributedString(markdown:baseDir:)` splits source around image refs; text segments → `parseMarkdownSegment` → `AttributedString(markdown:)` + `applyPresentationIntentStyling`; image refs → `resolveImageAttachment`
  4. **Display:** `NSAttributedString` published back via `applyRenderedResult` on `@MainActor` (guarded by generation counter) → `MarkdownRenderView.updateNSView` sets it on `NSTextView.textStorage`
  5. **Text selection:** standard `NSTextView` selection; ⌘C copies to `NSPasteboard`
  6. **Link click:** `NSTextViewDelegate.textView(_:clickedOnLink:at:)` → `file://` → `InterPanelRouter.open(url)`; `http/https/mailto` → `NSWorkspace.shared.open`; `javascript/data/blob` → blocked and logged

- **Editor→preview scroll sync (ISS-063):**
  - `WindowState.editorScrollFraction: Double?` (+ `AppState` pass-through) is written (throttled, >0.005 delta guard) by an `NSView.boundsDidChangeNotification` observer in `EditorView.makeNSView`
  - `MarkdownPreviewPanel` passes `appState.editorScrollFraction` as `syncScrollFraction: Double?` to `MarkdownRenderView` when sync is toggled on and `!viewModel.isLargeFile`; also passes `isLargeFile: viewModel.isLargeFile`
  - `MarkdownRenderView.updateNSView` applies sync scroll via the **owned** `NSScrollView` (the `nsView` parameter) at +0.02 s; `lastSyncScrollFraction` is committed inside the async block after the `scrollView` guard, so it is only marked applied when the scroll actually executes (ISS-090)
  - `MarkdownPreviewCoordinator.lastSyncScrollFraction` guards against feedback loops

- **AppKit-bridge containment (ISS-093, ISS-095, ISS-096):**
  - The bridge **owns its `NSScrollView`** (`makeNSView` returns `NSTextView.scrollableTextView()`); it never reads SwiftUI's private `enclosingScrollView`, which is not API-contracted and has broken between macOS releases. `MarkdownPreviewPanel` no longer wraps the view in a SwiftUI `ScrollView`.
  - The scroll-position observer is registered **once** in `makeNSView` against the owned clip view (stable for the view's lifetime) and removed in `dismantleNSView` — block-based `NotificationCenter` observers never release automatically (SW-2, ISS-093).
  - Print / save-as-PDF / save-as-Markdown closures are wired **once** in `makeNSView` onto `MarkdownPreviewCoordinator.{printAction, saveAsPDFAction, saveAsMarkdownAction}`; `updateNSView` no longer builds closures or mutates SwiftUI bindings (which risked "Modifying state during view update" — ISS-095). `MarkdownPreviewPanel` reads the actions off the coordinator and registers paired-preview actions as coordinator-delegating closures.

- **⌘-click source navigation (ISS-065):**
  - `MarkdownPreviewCoordinator.handleCommandClick(_:)` is an `@objc` handler on an `NSClickGestureRecognizer` installed in `MarkdownRenderView.makeNSView`
  - On ⌘-click: checks modifier key → guards against link clicks → looks up `viewModel.sourceMap` → calls `InterPanelRouter.revealSourceLine(_:)` → `EditorViewModel.revealLine(_:)` (in `EditorCommandHandling` protocol)
  - Disabled when `bidirectionalEnabled == false` or `viewModel.isLargeFile`

- **Large-file degraded mode (Step 10):**
  - `isLargeFile` is set when `text.utf16.count >= 80_000`; shown as "Large file — sync limited" in the toolbar
  - Scroll sync and ⌘-click navigation are both disabled; the render throttle delay is 0.30 s
  - Toolbar sync/bidir buttons are greyed out and `disabled(viewModel.isLargeFile)`

- **State owned:**
  - `MarkdownPreviewViewModel` — `renderedString`, `fontScale`, `isRendering`, `renderError`, `scrollOffset` (per-document scroll preservation wired — ISS-061 resolved), `isLargeFile`, `sourceMap`, `blockCache`
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
  - Very large document (>80k chars) → `isLargeFile = true`; throttle delay is 0.30 s; scroll sync and ⌘-click navigation are disabled; "Large file — sync limited" indicator shown. Render still runs on background Task via `RenderThrottle`; stale intermediate renders discarded by generation counter
  - Block cache miss on changed blocks → re-renders only changed blocks (O(delta)); unchanged blocks return from cache. Image blocks always re-render (never cached)
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
- `MarkdownPreviewCoordinator` holds `weak var viewModel: MarkdownPreviewViewModel?` — must be set by `MarkdownPreviewPanel.task` after configure; ⌘-click is a silent no-op when `nil`
- The `syncScrollFraction` parameter on `MarkdownRenderView` is `nil` when sync is disabled — `updateNSView` must guard on `nil` before applying any scroll, so that normal per-document scroll restore is unaffected
- `InterPanelRouter.revealSourceLine(_:)` and `EditorCommandHandling.revealLine(_:)` are the **only** path from preview → editor for ⌘-click navigation — this module never imports module 3 (SR-1)
- Block cache half-evicts (drops the oldest half) when count exceeds 500 — preserves recently-used entries rather than clearing everything; collision guard (`cached.text == block.text`) prevents a different block from reusing a cached render that shares its hash (ISS-091)
- `AppState.pairedPreviewPrintAction` and `AppState.pairedPreviewSaveAsPDFAction` are set by this panel to the live print/PDF closures when a `.markdown`/`.ascii` document is active; cleared on document type mismatch, no active document, or `.onDisappear` — the editor overflow menu and File menu read these to offer a "Plain Text / Rendered" choice

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
