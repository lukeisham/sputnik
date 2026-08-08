# Plan: Complete Module 8 — HTML Preview (integrate existing code + add missing panel)

**Created:** 2026-06-08  
**Module:** 8 HTML Preview  
**Build order position:** 7th (Foundation → Text Editor → Terminal → Project File Tree → Markdown Preview → PDF Viewer → **HTML Preview** → Resources)  
**Prerequisite modules completed:** Foundation (2), Text Editor (3), Terminal (7) ✅  
**Existing source:** 3 files already implemented (see below)  

---

## Summary

Module 8 already has 3 source files that implement the core renderer, link-navigation coordinator, and link policy. These were authored during the ISS-006 resolution and are well-aligned with the Module Guide. This plan identifies what's complete, what's missing, and specifies the single new file (`HTMLPreviewPanel.swift`) needed to finish the module — a top-level SwiftUI panel that wraps the existing `HTMLPreviewView` with a header bar and toolbar, matching the guide's diagram.

---

## Existing Code Audit

### File 1: `8 HTML Preview/HTMLPreviewView.swift` — ✅ Complete

**What it does:** `NSViewRepresentable` wrapping `WKWebView`. Renders the active `.html` document via `loadHTMLString(_:baseURL:)`. Shows a placeholder when the active document is not `.html` or `nil`. Passes `baseURL` (file directory) to the coordinator so relative paths in `src`/`href` resolve correctly. JavaScript is disabled for security.

**Guide alignment:** Matches the `HTMLPreviewView` type spec exactly — pure function of `AppState.activeDocument`, owns no document state, SW-3 AppKit bridge justified.

**Coding rules:** SR-1 ✅ (only talks to Foundation via `@Environment(AppState.self)`), SR-2 ✅ (safe `guard let`), SR-3 ✅ (no text copy — reads `session.text` directly), SW-2 ✅ (router held weakly in coordinator), SW-3 ✅ (justified in doc comment), SW-4 ✅ (thorough doc comments).

### File 2: `8 HTML Preview/HTMLPreviewCoordinator.swift` — ✅ Complete

**What it does:** `NSViewRepresentable.Coordinator` conforming to `WKNavigationDelegate`. Intercepts every navigation, applies `LinkNavigationPolicy.decide()`, and routes: in-page anchors → `.allow`, local files → `InterPanelRouter.open(_:)`, external URLs → `NSWorkspace.shared.open(_:)`, unsafe schemes → `.cancel` + log. Holds `router` weakly (SW-2).

**Guide alignment:** Matches the `HTMLPreviewCoordinator` type spec exactly.

**Coding rules:** SR-1 ✅, SW-1 ✅ (`@MainActor`), SW-2 ✅ (`weak var router`, `[weak self]` in Task), SW-4 ✅.

### File 3: `8 HTML Preview/LinkNavigationPolicy.swift` — ✅ Complete

**What it does:** Pure function `decide(for:targetIsBlank:currentBaseURL:) -> Decision` — no WebKit types in its signature. Classifies: in-page `#anchor` → `.allowInPage`, `file://` → `.openAsTab`, `http(s)`/`mailto` → `.openExternally`, `javascript:`/`data:`/`blob` → `.block`. Unit-testable in isolation.

**Guide alignment:** Matches the `LinkNavigationPolicy` type spec exactly.

**Coding rules:** SR-5 ✅ (pure Foundation), SW-4 ✅.

---

## Gap Analysis

### What the guide's diagram shows vs what exists

| Diagram element | Exists? | Location |
|---|---|---|
| WKWebView render area | ✅ | `HTMLPreviewView` |
| Link navigation interception | ✅ | `HTMLPreviewCoordinator` + `LinkNavigationPolicy` |
| Placeholder (no `.html` active) | ✅ | `HTMLPreviewView.placeholderHTML` |
| Header bar — document title + overflow menu [⋯] | ❌ | Missing |
| Toolbar — [🔍 Fit Width] button | ❌ | Missing |
| Toolbar — [🔗 Link Navigation] toggle | ❌ | Missing |
| Error banner for load failures | ❌ | Missing (coordinator logs to console but no UI) |
| SwiftUI panel container | ❌ | Missing (`HTMLPreviewView` is just the `NSViewRepresentable`) |

### What needs to be added: `HTMLPreviewPanel.swift`

A single new top-level SwiftUI view that:
- Wraps the existing `HTMLPreviewView` in a panel shell
- Adds a header bar with the active document filename
- Adds toolbar buttons (Fit Width toggle, Link Navigation toggle)
- Handles the three display states: rendering, wrong-type placeholder, no-document empty state
- Surfaces load errors as a subtle inline banner

---

## New File to Create

### `8 HTML Preview/HTMLPreviewPanel.swift`

**Responsibility:** Top-level SwiftUI view — the entry point wired into the app's layout system at `PanelPosition.right` (or wherever assigned). Assembles header, toolbar, and the existing `HTMLPreviewView`.

**Layout (matching guide's diagram):**
```
┌──────────────────────────────────────────────────────────┐
│  HTML PREVIEW — <filename.html>                    [⋯]   │
│  Toolbar: [🔍 Fit Width]  [🔗]                            │
│  ──────────────────────────────────────────────────────── │
│                                                           │
│  HTMLPreviewView (WKWebView via NSViewRepresentable)      │
│                                                           │
└──────────────────────────────────────────────────────────┘
```

**Sub-components:**

- **Header bar:**
  - Document title: `"HTML Preview — \(activeDocument?.url?.lastPathComponent ?? "No file open")"`
  - Overflow menu `[⋯]`: "Reveal in Finder" for source file, "Reload Preview" (forces `loadHTMLString` again)

- **Toolbar (2 buttons):**
  - **Fit Width** `[🔍]`: Toggles `isFitWidth: Bool` state. When enabled, wraps the `HTMLPreviewView` in a centred container with `maxWidth: 960pt`; when disabled, fills the full panel width. (Implementation: `@State private var isFitWidth = true` — toggles the `.frame(maxWidth:)` modifier on `HTMLPreviewView`.)
  - **Link Navigation** `[🔗]`: Toggles `isLinkNavigationEnabled: Bool` state. When disabled, the coordinator skips `LinkNavigationPolicy` and `.cancel`s all navigations. (Implementation: `@State private var isLinkNavigationEnabled = true` — passed to coordinator/View; when disabled, coordinator returns `.cancel` for all non-`.other` navigations.)

- **Content area:**
  - **Active + HTML:** Shows `HTMLPreviewView(router: router)`.
  - **Active + Not HTML:** Shows placeholder text — `"\(filename) is a \(fileType) file, not HTML"` with muted styling.
  - **No active document:** Shows empty-state — `"Open an HTML file to preview"`.
  - **Load error:** Subtle banner at top with error message (surface coordinator navigation-failure errors to SwiftUI via a published `loadError: String?` property on the coordinator or a callback).

**Dependencies:**
```swift
@Environment(AppState.self) private var appState
@State private var isFitWidth = true
@State private var isLinkNavigationEnabled = true
```
Receives `router: (any InterPanelRouter)?` at init, passed through to `HTMLPreviewView`.

**State transitions:**

```
activeDocument?.fileType
    ├── nil          → empty-state placeholder
    ├── .html        → HTMLPreviewView
    └── anything else → wrong-type placeholder
```

---

## Minor Updates to Existing Files

### `HTMLPreviewCoordinator.swift` — Add link-navigation toggle support

Add an optional `isLinkNavigationEnabled: Bool` property (default `true`). When `false`, the `decidePolicyFor` delegate method skips `LinkNavigationPolicy.decide()` and immediately calls `decisionHandler(.cancel)` for all non-`.other` navigations. This allows the toolbar `[🔗]` toggle to disable link clicks.

```swift
/// When `false`, all link clicks are suppressed — the preview becomes read-only.
/// Toggled by the `[🔗]` button in `HTMLPreviewPanel`.
var isLinkNavigationEnabled: Bool = true
```

In `webView(_:decidePolicyFor:decisionHandler:)`, add at the top after the `.other` guard:
```swift
guard isLinkNavigationEnabled else {
    decisionHandler(.cancel)
    return
}
```

### `HTMLPreviewCoordinator.swift` — Surface load errors

Expose a `loadError` callback or `@Published` property so the panel can show an error banner:
```swift
/// Called when a navigation fails; the panel can display this as a banner.
var onLoadError: ((String) -> Void)?
```
Set in `webView(_:didFail:withError:)`:
```swift
onLoadError?(error.localizedDescription)
```

---

## Implementation Order

1. **Update `HTMLPreviewCoordinator.swift`** — add `isLinkNavigationEnabled` toggle + `onLoadError` callback (small, additive changes)
2. **Create `HTMLPreviewPanel.swift`** — new top-level panel wrapping the existing view

No changes needed to `HTMLPreviewView.swift` or `LinkNavigationPolicy.swift` — both are complete as-is.

---

## Files Summary

| File | Status | Action |
|---|---|---|
| `HTMLPreviewView.swift` | ✅ Exists | No changes |
| `HTMLPreviewCoordinator.swift` | ✅ Exists | Minor: add toggle + error callback |
| `LinkNavigationPolicy.swift` | ✅ Exists | No changes |
| `HTMLPreviewPanel.swift` | ❌ Missing | **Create** — panel shell with header + toolbar |

---

## Integration Points

| Point | Foundation API | Usage |
|---|---|---|
| Active document detection | `AppState.activeDocument` | Panel decides which state to render |
| Document title | `activeDocument?.url?.lastPathComponent` | Header bar label |
| Link → local file | `InterPanelRouter.open(_:)` | Already handled by coordinator |
| Link → external | `NSWorkspace.shared.open(_:)` | Already handled by coordinator |
| Reveal in Finder | `NSWorkspace.shared.activateFileViewerSelecting([url])` | Overflow menu action |
| Styling | `SputnikColor`, `SputnikSpacing`, `SputnikFont` | Header, toolbar, placeholder styling |
| Layout slot | `PanelPosition.right` | Default assignment in `PanelLayout.default` |

---

## Coding Rule Compliance Checklist

- [ ] **SR-1:** Panel communicates only through Foundation (`AppState`, `InterPanelRouter`, design tokens); owns no document state
- [ ] **SR-2:** No force-unwraps; safe optional chaining for `activeDocument?.url`; nil router handled gracefully
- [ ] **SR-3:** Panel is a thin view wrapper — no text copies; the `WKWebView` is released when the panel is unmounted
- [ ] **SR-4:** No heavy work on main thread; HTML loading is `WKWebView`'s own async pipeline
- [ ] **SR-5:** Uses `WKWebView` (WebKit), `NSWorkspace` (AppKit), SwiftUI — all Apple frameworks
- [ ] **SR-6:** New `HTMLPreviewPanel.swift` has one responsibility: panel chrome (header + toolbar + state switching). Existing files already satisfy SR-6.
- [ ] **SW-1:** `@MainActor` on coordinator; `@Environment(AppState.self)` in panel
- [ ] **SW-2:** Coordinator already uses `weak var router` and `[weak self]` in Task — unchanged
- [ ] **SW-3:** Existing `NSViewRepresentable` for `WKWebView` already justified — no new AppKit bridges
- [ ] **SW-4:** Doc comments on new `HTMLPreviewPanel` following triple-slash convention
- [ ] **MR-3:** No new background work — HTML rendering is WKWebView's built-in async pipeline

---

## Handling ISS-006

ISS-006 originally covered both preview panels. After this plan is implemented:
- Module 8: guide ✅, source ✅ (3 existing + 1 new), panel ✅
- Module 4: guide ✅, plan exists in `Plans New/`
- Update `References/Issues.md`: ISS-006 → `Resolved` once both modules 4 and 8 are complete

---

## After Implementation

1. Verify `HTMLPreviewPanel` compiles and renders correctly in the layout
2. Smoke tests:
   - Open an `.html` file → preview renders in WKWebView with header showing filename
   - Toggle Fit Width → view centres with max-width or fills panel
   - Toggle Link Navigation off → click a link → nothing happens
   - Toggle Link Navigation on → click `http://` link → opens in browser
   - Click `file://` link to another `.html`/`.md` → opens as new editor tab
   - Switch to a `.md` tab → preview shows "not HTML" placeholder
   - Close all tabs → empty-state placeholder
   - Reveal in Finder from overflow menu → Finder opens to source file
3. Update the Module Guide: `status: draft` → `status: complete`, update `last_updated`
4. Move this plan to `Plans Completed/`
