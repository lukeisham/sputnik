# Plan: Implement Module 4 — Markdown Preview

**Created:** 2026-06-08  
**Module:** 4 Markdown Preview  
**Build order position:** 5th (Foundation → Text Editor → Terminal → Project File Tree → **Markdown Preview** → PDF Viewer → HTML Preview → Resources)  
**Prerequisite modules completed:** Foundation (2), Text Editor (3), Terminal (7), Project File Tree (6 → in plan/active) ✅  
**Related module complete:** HTML Preview (8) — patterns for coordinator + link policy  

---

## Summary

Create 4 source files in `4 Markdown Preview/` implementing a live-rendered Markdown preview panel in the centre lower layout slot. The panel observes `AppState.activeDocument`, converts `.markdown` text to a styled `AttributedString` via `AttributedString(markdown:)` on a background task, and renders it in a read-only, selectable, link-interactive `NSTextView` via `NSViewRepresentable`. Link clicks are intercepted by an `NSTextViewDelegate` coordinator and routed to `InterPanelRouter.open(_:)` (local files) or `NSWorkspace.shared.open(_:)` (external URLs), with unsafe schemes blocked.

---

## Pre-flight Checks

### Foundation APIs available (verified from source)

| Need | Available? | API |
|---|---|---|
| Active document identity | ✅ | `AppState.activeDocumentID: UUID?` |
| Active document text & type | ✅ | `AppState.activeDocument: DocumentSession?` (.text, .fileType) |
| Open file from link click | ✅ | `InterPanelRouter.open(_ url: URL) async` |
| Error alert | ✅ | `SputnikAlert.custom(title:message:)` |
| Design tokens | ✅ | `SputnikColor`, `SputnikSpacing`, `SputnikFont` |
| Panel layout slot | ✅ | `PanelPosition.centerLower` — default slot for Markdown Preview |

### MacOS APIs available

| Need | API |
|---|---|
| Markdown → styled text | `AttributedString(markdown:)` (macOS 15+, iOS 18+) |
| Read-only selectable text | `NSTextView` with `isEditable = false`, `isSelectable = true` |
| Link interaction | `NSTextViewDelegate.textView(_:clickedOnLink:at:)` |
| External URL open | `NSWorkspace.shared.open(_:)` |

### Issues to note

- **ISS-006** (partially resolved) — the issue originally noted "no Module Guide exists for Markdown Preview." The guide now exists; this plan addresses the remaining "source code outstanding" portion. After implementation, ISS-006 can be marked fully resolved.

---

## Files to Create

### 1. `4 Markdown Preview/MarkdownPreviewViewModel.swift`

**Responsibility:** `@Observable` `@MainActor` class — owns the rendered output, observes the active Markdown document, and orchestrates the parse pipeline.

**Owned state:**
- `renderedString: AttributedString` — the latest successfully parsed Markdown output (empty by default)
- `scrollOffset: CGFloat` — preserved vertical scroll position across re-renders
- `fontScale: CGFloat` — user-adjustable zoom (default 1.0; range 0.5…2.0)
- `isRendering: Bool` — `true` while a background parse is in flight
- `renderError: String?` — non-nil when `AttributedString(markdown:)` threw (surface as a subtle banner, never crash)

**Methods:**
- `func startObserving(appState: AppState)` — subscribes to `AppState.activeDocumentID` changes and the active session's `.text` publisher (via `withObservationTracking` or `@Observable` cascade) to trigger re-renders
- `func render(markdown: String) async` — runs `AttributedString(markdown:)` on `Task(priority: .utility)`; on success, publishes `renderedString` on `@MainActor`; on failure, captures error message and renders the raw text as fallback plain-text `AttributedString`
- `func render(markdown: String, fontScale: CGFloat) async` — as above but applies a font-size scale to the base system font sizes in the attributed string (walk the runs, adjust `.font` attribute)

**Threading (MR-3, SW-1):**
- `render(markdown:)` dispatches conversion to `Task.detached(priority: .utility)`, returns `AttributedString` (which is `Sendable`) to `@MainActor` for assignment
- A stale-render guard: if a newer `render` call arrives before the previous completes, the older task's result is discarded (compare a generation counter or the input text hash)

**Dependency injection:**
- Receives `AppState` via the SwiftUI `@Environment` in the panel view; the ViewModel can hold a weak reference or be driven by the view layer pushing text changes

**Design rationale:** Separation of the ViewModel from the view keeps the parse pipeline testable independently of `NSTextView`. The ViewModel is a pure function of the active session's text — it owns no document state (SR-1, SR-3).

---

### 2. `4 Markdown Preview/MarkdownPreviewCoordinator.swift`

**Responsibility:** `NSViewRepresentable.Coordinator` conforming to `NSTextViewDelegate`. Intercepts link clicks on the rendered Markdown and routes them safely.

**Conforms to:** `NSTextViewDelegate`

**Properties:**
- `weak var router: (any InterPanelRouter)?` — held weakly via `any InterPanelRouter` existential to avoid retain cycles (SW-2)

**Delegate method:**
```swift
func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool
```

**Link routing logic (matching `LinkNavigationPolicy` philosophy):**
1. Extract the URL from `link` (it may be `URL`, `String`, or `NSURL`)
2. **`file://` URLs:** → `router.open(url)` → opens as new editor tab. Return `true` (handled).
3. **`http://` / `https://` / `mailto:` URLs:** → `NSWorkspace.shared.open(url)` → system browser / mail client. Return `true` (handled).
4. **`javascript:` / `data:` / other unsafe schemes:** → blocked and logged. Return `true` (handled — prevent default).
5. **Unknown / nil:** → return `false` (let system try).

**Threading:** All `NSTextViewDelegate` callbacks are main-thread; router methods are `@MainActor` — no actor hop needed.

**Note:** `LinkNavigationPolicy` (module 8) could be promoted to Foundation as a shared utility, but per the guide's "similar to" phrasing and SR-1, the coordinator defines its own inline link classification. This is a future refactor opportunity to note.

---

### 3. `4 Markdown Preview/MarkdownRenderView.swift`

**Responsibility:** `NSViewRepresentable` wrapping an `NSTextView`. Configures the text view for read-only, selectable, link-interactive Markdown display.

**AppKit bridge rationale (SW-3):** SwiftUI's built-in `Text` view does not support text selection, clipboard copy, or clickable link callbacks. `NSTextView` provides all three natively and is the appropriate AppKit interop path.

**`makeNSView`:**
- Create `NSTextView` with a zero frame
- Configure:
  - `isEditable = false`
  - `isSelectable = true`
  - `isRichText = true`
  - `allowsUndo = false`
  - `isAutomaticLinkDetectionEnabled = false` (links come from `AttributedString`, not auto-detect)
  - `backgroundColor = NSColor(SputnikColor.editorBackground)` (match editor)
  - `textContainerInset = NSSize(width: 16, height: 16)` (comfortable padding)
  - `textContainer?.widthTracksContainer = true`
  - Disable scroll bar (scroll is handled by SwiftUI `ScrollView` wrapping the representable, or use `NSScrollView`)
- Assign `delegate = context.coordinator`

**`updateNSView`:**
- Guard: if `viewModel.renderedString` differs from the current `textStorage` content, apply it
- Apply `viewModel.fontScale` to the text view's default font size before setting the attributed string
- Preserve `viewModel.scrollOffset` by restoring the visible rect after the text update (if the document hasn't changed size dramatically, approximate restoration)

**Size calculation:** The `NSViewRepresentable` should report its intrinsic content size based on the text layout so the SwiftUI `ScrollView` can scroll naturally. Override `intrinsicContentSize` via a custom `NSTextView` subclass or use `textContainer?.containerSize` with `heightTracksTextView = false` and a fixed width.

---

### 4. `4 Markdown Preview/MarkdownPreviewPanel.swift`

**Responsibility:** Top-level SwiftUI view — assembles the toolbar and the `MarkdownRenderView`. The single entry point wired into the app's layout system.

**Layout (matching guide's diagram):**
```
┌──────────────────────────────────────────────────────────┐
│  MARKDOWN PREVIEW — <filename.md>                   [⋯]  │
│  Toolbar: [🔍 Fit Width]  [Aa]  [🔗]                     │
│  ──────────────────────────────────────────────────────── │
│                                                           │
│  Rendered Markdown content (NSTextView via                │
│  MarkdownRenderView)                                      │
│                                                           │
└──────────────────────────────────────────────────────────┘
```

**Sub-components:**

- **Header bar:**
  - Document title: `activeDocument?.url?.lastPathComponent ?? "Markdown Preview"`
  - Overflow menu `[⋯]`: shortcut to "Reveal in Finder" for the source file

- **Toolbar (3 buttons):**
  - **Fit Width** `[🔍]`: Toggles between fixed-width centred layout and full-width layout. (Implementation: adjusts `NSTextView`'s `textContainer?.containerSize.width` or wraps the text view in a centred frame with a max width like `720pt`.)
  - **Font Size** `[Aa]`: Cycles through predefined zoom levels (0.8×, 1.0×, 1.2×, 1.5×) or opens a small popover with a `Slider`. Binds to `viewModel.fontScale`.
  - **Link toggle** `[🔗]`: Shows whether links are interactive (default: on). Toggling off disables link-click handling in the coordinator (all clicks become selection-only).

- **Content area:**
  - **Active + Markdown:** Shows `MarkdownRenderView` fed by `viewModel.renderedString`.
  - **Active + Not Markdown:** Shows placeholder — "No Markdown file open" with the active document's filename and a note that it's a `.html`/`.txt`/etc. file.
  - **No active document:** Shows empty-state placeholder — "Open a Markdown file to preview."
  - **Render error:** Subtle banner at top of content area with `viewModel.renderError` message; content falls back to plain-text `AttributedString` of the raw markdown.

**Dependencies:**
- `@Environment(AppState.self) private var appState`
- Receives `router: (any InterPanelRouter)?` at init, passed to `MarkdownPreviewCoordinator`
- Creates `MarkdownPreviewViewModel` as `@State private var viewModel`
- Observes `appState.activeDocument` → triggers `viewModel.render(markdown:)` on text change

---

## Implementation Order

1. **`MarkdownPreviewViewModel.swift`** — pure logic, no AppKit dependency; testable in isolation
2. **`MarkdownPreviewCoordinator.swift`** — depends on `InterPanelRouter` (Foundation), no View dependency
3. **`MarkdownRenderView.swift`** — depends on ViewModel + Coordinator; the AppKit bridge
4. **`MarkdownPreviewPanel.swift`** — depends on all above; assembles final UI

---

## Integration Points

| Point | Foundation API | Usage |
|---|---|---|
| Active document detection | `AppState.activeDocument` | Panel shows placeholder when `fileType != .markdown` or `nil` |
| Source text | `DocumentSession.text` | Fed to `AttributedString(markdown:)` for rendering |
| Link → local file | `InterPanelRouter.open(_:)` | Link clicks on `file://` URLs open new editor tab |
| Link → external | `NSWorkspace.shared.open(_:)` | `http(s)` / `mailto` → system browser/mail |
| Error banner | `SputnikAlert.custom` / inline banner | Markdown parse failure → subtle warning |
| Styling | `SputnikColor`, `SputnikSpacing`, `SputnikFont` | Toolbar, placeholder, error banner styling |
| Layout slot | `PanelPosition.centerLower` | Default assignment in `PanelLayout.default` |

---

## Coding Rule Compliance Checklist

- [ ] **SR-1:** Only communicates through Foundation (`AppState`, `InterPanelRouter`, design tokens); owns no document state — pure function of active session
- [ ] **SR-2:** No force-unwraps; `AttributedString(markdown:)` wrapped in `do/catch` with plain-text fallback; link value extraction uses `guard let` / `as?` casting; nil router is handled (links become inactive)
- [ ] **SR-3:** `AttributedString` is the only in-memory representation of the rendered document; raw text is referenced from `DocumentSession.text`, not copied; `NSTextView` holds a single `NSTextStorage` reference
- [ ] **SR-4:** Markdown parsing on `Task(priority: .utility)`; `@MainActor` for all view/AppKit mutations; stale render guard prevents redundant work (generation counter)
- [ ] **SR-5:** Uses `AttributedString(markdown:)` (Foundation), `NSTextView` (AppKit), `NSWorkspace` — all Apple frameworks; no third-party Markdown parsers
- [ ] **SR-6:** One responsibility per file — 4 files as listed above
- [ ] **SW-1:** `async/await`, `Task.detached(priority: .utility)` for parsing; `@MainActor` on ViewModel and ViewRepresentable; `AttributedString` is `Sendable`
- [ ] **SW-2:** `[weak self]` in coordinator's router reference and any escaping closures; audit for cycles between `NSTextView` ↔ delegate ↔ coordinator
- [ ] **SW-3:** `NSViewRepresentable` for `NSTextView` — justified in guide: "SwiftUI's `Text` does not support text selection"
- [ ] **SW-4:** Doc comments on all public types/methods following the triple-slash `///` convention
- [ ] **MR-3:** `.utility` priority for background Markdown parsing

---

## Handling ISS-006

ISS-006 ("No Module Guide exists for the preview panels") was marked partially resolved after the HTML Preview was built. The Markdown Preview guide now exists. After this plan is implemented:
- Update `References/Issues.md`: ISS-006 → status `Resolved`, note that both modules 4 and 8 have guides + source.

---

## After Implementation

1. Verify the module compiles cleanly (no cross-module import violations)
2. Verify the panel integrates into the main `AppOverview` layout at `PanelPosition.centerLower`
3. Manual smoke tests:
   - Open a `.md` file → preview renders with headings, bold, italic, code, links, tables, lists
   - Click a `http://` link → opens in browser
   - Click a `[local file](other.md)` link → opens as new editor tab
   - Select text + ⌘C → copies to clipboard
   - Switch to a `.html` tab → preview shows "No Markdown" placeholder (no stale render)
   - Close all tabs → preview shows empty-state placeholder
   - Toggle Fit Width → text reflows
   - Adjust font scale → text sizes change
   - Inject malformed Markdown → parse error banner, plain-text fallback
4. Update the Module Guide: `status: draft` → `status: complete`, update `last_updated`
5. Update `Issues.md`: ISS-006 → `Resolved`
6. Move this plan to `Plans Completed/`
