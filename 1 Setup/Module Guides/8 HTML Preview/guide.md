---
module: 8 HTML Preview
status: draft
last_updated: 2026-06-08
---

## Purpose
Render the active editor tab's HTML (supporting the **HTML Living Standard**) to a live, scroll-synced web preview, and intercept link clicks so that local links open as new editor tabs rather than navigating the preview away from the file the editor is showing.

## Diagram

```
  Foundation (2.2)                         Module 8 — HTML Preview panel
  ┌────────────────────────┐               ┌──────────────────────────────────┐
  │ AppState               │   observes    │  HTMLPreviewView (NSViewRep.)     │
  │  activeDocumentID ─────┼──────────────▶│   wraps WKWebView                 │
  │  openDocuments[…]      │               │                                   │
  └────────────────────────┘               │  active doc is .html ?            │
            ▲                               │     yes → loadHTMLString(text,   │
            │ writes via router (2.1)       │            baseURL: file dir)     │
            │                               │     no  → panel shows placeholder │
  ┌────────────────────────┐               └───────────────┬──────────────────┘
  │ Text Editor (3.4)      │                               │ user clicks a link
  │  edits .html text ─────┼── debounced text ────────────▶│
  │  "Render as HTML" ⌘⌥P  │                               ▼
  └────────────────────────┘             ┌──────────────────────────────────────┐
                                         │  WKNavigationDelegate                 │
                                         │  decidePolicyFor(navigationAction)    │
                                         ├──────────────────────────────────────┤
                                         │  #anchor (same page)  → .allow        │
                                         │  local .html / file:// → .cancel,     │
                                         │     InterPanelRouter.open(url)  ──────┼─▶ new editor tab (3)
                                         │  local .md / .pdf / …  → .cancel,     │       │
                                         │     InterPanelRouter.open(url)        │       └─▶ routed to 4 / 5
                                         │  http(s) / target=_blank → .cancel,   │
                                         │     NSWorkspace.shared.open(url)  ─────┼─▶ system browser
                                         └──────────────────────────────────────┘
```

## Technical Summary
- **Framework(s):** WebKit (`WKWebView`, `WKNavigationDelegate`), SwiftUI (`NSViewRepresentable`), AppKit. Target rendering is the **HTML Living Standard** (WebKit/Safari).
- **Key types:**
  - `HTMLPreviewView` — `NSViewRepresentable` wrapping a single `WKWebView`; observes `AppState.activeDocumentID` and re-renders when the active document changes or its text mutates (SW-3: AppKit bridge is justified because `WKWebView` has no SwiftUI equivalent) <!-- assumed -->
  - `HTMLPreviewCoordinator` — the `NSViewRepresentable.Coordinator`; conforms to `WKNavigationDelegate` and owns the link-navigation policy; holds a `weak` reference to the router, never a strong `self` capture in delegate callbacks (SW-2) <!-- assumed -->
  - `LinkNavigationPolicy` — pure function `decide(for: URL, targetIsBlank: Bool, workspace: URL?) -> Decision` returning `.allowInPage` / `.openAsTab(URL)` / `.openExternally(URL)`; unit-testable in isolation, no WebKit types in its signature <!-- assumed -->
  - Consumes Foundation types only: `DocumentSession` and `activeDocumentID` (2.2), `InterPanelRouter` (2.1), `FileType` (2.1) — this module owns no document state of its own (SR-1)
- **Threading model:** All `WKWebView` calls and the render path are `@MainActor`. Re-render is triggered by observing `activeDocumentID` and the active session's debounced text (debounce lives in 3.4, not here). HTML string assembly is trivial and stays on the main thread; no background Task is needed for preview itself.
- **Data flow:**
  - *Render:* `activeDocumentID` changes (or active `.html` session text changes) → `HTMLPreviewView` reads the active `DocumentSession.text` → `webView.loadHTMLString(text, baseURL:)` with `baseURL` set to the file's directory so relative `src`/`href` resolve.
  - *Sync:* the preview never tracks a file URL directly — it renders **whatever document is active**. Switching editor tabs switches the preview with no extra binding (see Failure modes / SR-1). This is the answer to "which preview syncs to which editor": there is one active document, and the preview is a pure function of it.
  - *Link click:* `WKNavigationDelegate.webView(_:decidePolicyFor:decisionHandler:)` → `LinkNavigationPolicy.decide(…)` → in-page anchors `.allow`; local files `.cancel` + `InterPanelRouter.open(url)` (opens/raises a tab via Foundation 2.1); external `http(s)` or `target="_blank"` `.cancel` + `NSWorkspace.shared.open(url)`.
- **State owned:** None persistent. Holds only the live `WKWebView` instance and its coordinator; the document text and active-tab identity are owned by Foundation `AppState` (2.2). This keeps the panel disposable and low-RAM (SR-3) — closing the panel releases the web view.
- **Dependencies:** Foundation 2.2 (`AppState.activeDocumentID`, `DocumentSession`); Foundation 2.1 (`InterPanelRouter.open(_:)`, `FileType`); Text Editor 3.4 (source of `.html` text + the "Render as HTML" command); Foundation 2.4 (placeholder/empty-state styling, `SputnikAlert` for load errors).
- **Failure modes:**
  - Active document is not `.html` → panel shows a neutral placeholder; it does **not** render stale content from a previously active tab.
  - Link target is a local file that no longer exists → `InterPanelRouter.open(_:)` classifies it and surfaces a `SputnikAlert` (2.4); the preview is left unchanged, never blanked.
  - External link with an unexpected scheme (`javascript:`, `data:`, `mailto:` …) → not auto-navigated; `mailto:` is handed to `NSWorkspace`, all other non-`http(s)` schemes are `.cancel`led and logged, never executed in-page (defensive default).
  - Very large HTML string → rendering is bounded by the editor's existing file-size guard (module 3 spec, SR-3); module 8 adds no second copy of the text — it reads the active session's buffer.
  - Web content tries to navigate the top frame on its own (meta refresh, script) → treated like any navigation: same `LinkNavigationPolicy` applies, so it cannot silently desync the preview from the editor.

## Spec Reference
> Extracted verbatim from `readme.md`:

```
Foundation → Text Editor Window → Project File Tree → Markdown Preview → PDF Viewer → HTML Preview → Terminal

8 | HTML Preview | Live HTML preview, synced to editor
```

> Related editor spec the preview is driven by:

```
3. EDITOR WINDOW …
  11. HTML language support (Inline Suggestions / Ghost Text, Debouncing)
```
