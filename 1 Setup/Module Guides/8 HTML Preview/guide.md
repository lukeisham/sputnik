---
module: 8 HTML Preview
status: complete
last_updated: 2026-06-09
plan: 1 Setup/Plans Completed/2026-06-08 8 HTML Preview Complete HTML Preview module.md
---

## Purpose
Render the active editor tab's HTML (supporting the **HTML Living Standard**) to a live, scroll-synced web preview, and intercept link clicks so that internal links (other Sputnik-compatible files like `.html`, `.md`, `.pdf`) open as new editor tabs within the app, while external URLs (`http`/`https`) open in the user's default web browser.

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
                                         │     NSWorkspace.shared.open(url)  ─────┼─▶ default browser
                                         └──────────────────────────────────────┘
```

## Technical Summary
- **Framework(s):** WebKit (`WKWebView`, `WKNavigationDelegate`), SwiftUI (`NSViewRepresentable`), AppKit. Target rendering is the **HTML Living Standard** (WebKit/Safari).
- **Key types:**
  - `HTMLPreviewView` — `NSViewRepresentable` wrapping a single `WKWebView`; observes `AppState.activeDocumentID` and re-renders when the active document changes or its text mutates (SW-3: AppKit bridge is justified because `WKWebView` has no SwiftUI equivalent)
  - `HTMLPreviewCoordinator` — the `NSViewRepresentable.Coordinator`; conforms to `WKNavigationDelegate` and owns the link-navigation policy; also conforms to `WKScriptMessageHandler` to receive selection-change messages from the injected script; holds a `weak` reference to the router, never a strong `self` capture in delegate callbacks (SW-2)
  - `MoreContextWebView` — `WKWebView` subclass that overrides `willOpenMenu(_:with:)` to inject "More Context: Grammar Help" and "More Context: HTML Help" items into the right-click context menu via the shared `MoreContextMenu.items(...)` builder (2.7); reads `capturedSelection` from the coordinator (populated by the `selectionchange` script message)
  - `LinkNavigationPolicy` — pure function `decide(for: URL, targetIsBlank: Bool, currentBaseURL: URL?) -> Decision` returning `.allowInPage` / `.openAsTab(URL)` / `.openExternally(URL)` / `.block`; unit-testable in isolation, no WebKit types in its signature
  - Consumes Foundation types only: `DocumentSession` and `activeDocumentID` (2.2), `InterPanelRouter` (2.1), `FileType` (2.1), `MoreContextMenu` (2.7), `HelpContextResolving` (2.7) — this module owns no document state of its own (SR-1)
- **Threading model:** All `WKWebView` calls and the render path are `@MainActor`. Re-render is triggered by observing `activeDocumentID` and the active session's debounced text (debounce lives in 3.4, not here). HTML string assembly is trivial and stays on the main thread; no background Task is needed for preview itself.
- **Data flow:**
  - *Render:* `activeDocumentID` changes (or active `.html` session text changes) → `HTMLPreviewView` reads the active `DocumentSession.text` → `webView.loadHTMLString(text, baseURL:)` with `baseURL` set to the file's directory so relative `src`/`href` resolve.
  - *Security:* `configuration.defaultWebpagePreferences.allowsContentJavaScript = false` (ISS-010) — disables author-injected JS while allowing the app's own `WKUserScript` for selection capture; replaces the previous `javaScriptEnabled = false` which blocked both
  - *Selection capture:* A `WKUserScript` injected at `atDocumentEnd` listens for `selectionchange` events and posts the selected text via `window.webkit.messageHandlers.selectionChange.postMessage(...)`; the coordinator's `WKScriptMessageHandler.didReceive(_:)` stores the selection in `capturedSelection` — this is read synchronously by `MoreContextWebView.willOpenMenu(_:with:)` (since `willOpenMenu` is synchronous and cannot query the web view directly)
  - *More Context:* `MoreContextWebView.willOpenMenu(_:with:)` inserts two items at the top of the right-click menu: "More Context: Grammar Help" (`.grammar` kind) and "More Context: HTML Help" (`.html` kind), using the cached `capturedSelection` and the shared resolver; the `onRequest` sink writes the resolved `HelpRequest` to `AppState.requestedHelpTarget`
  - *Sync:* the preview never tracks a file URL directly — it renders **whatever document is active**. Switching editor tabs switches the preview with no extra binding (see Failure modes / SR-1). This is the answer to "which preview syncs to which editor": there is one active document, and the preview is a pure function of it.
  - *Link click:* `WKNavigationDelegate.webView(_:decidePolicyFor:decisionHandler:)` → `LinkNavigationPolicy.decide(…)` → in-page `#anchor` scrolls in place (`.allow`); internal local files (`.html`, `.md`, `.pdf`, and other Sputnik-compatible types) are opened as **new editor tabs** within the app via `InterPanelRouter.open(url)` (`.cancel` + route to Foundation 2.1); external `http(s)` URLs or `target="_blank"` links are opened in the user's **default web browser** via `NSWorkspace.shared.open(url)` (`.cancel`).
- **State owned:** None persistent. Holds only the live `WKWebView` instance and its coordinator; the document text and active-tab identity are owned by Foundation `AppState` (2.2). This keeps the panel disposable and low-RAM (SR-3) — closing the panel releases the web view.
- **Dependencies:** Foundation 2.2 (`AppState.activeDocumentID`, `DocumentSession`); Foundation 2.1 (`InterPanelRouter.open(_:)`, `FileType`); Text Editor 3.4 (source of `.html` text + the "Render as HTML" command); Foundation 2.4 (placeholder/empty-state styling, `SputnikAlert` for load errors); Foundation 2.7 (`MoreContextMenu`, `HelpContextResolving`, `HelpContextQuery`).
- **Failure modes:**
  - Active document is not `.html` → panel shows a neutral placeholder; it does **not** render stale content from a previously active tab.
  - Link target is a local file that no longer exists → `InterPanelRouter.open(_:)` classifies it and surfaces a `SputnikAlert` (2.4); the preview is left unchanged, never blanked.
  - External link with an unexpected scheme (`javascript:`, `data:`, `mailto:` …) → not auto-navigated; `mailto:` is handed to `NSWorkspace`, all other non-`http(s)` schemes are `.cancel`led and logged, never executed in-page (defensive default).
  - Very large HTML string → rendering is bounded by the editor's existing file-size guard (module 3 spec, SR-3); module 8 adds no second copy of the text — it reads the active session's buffer.
  - Web content tries to navigate the top frame on its own (meta refresh, script) → treated like any navigation: same `LinkNavigationPolicy` applies, so it cannot silently desync the preview from the editor.
  - `WKScriptMessageHandler` registration creates a potential retain cycle between `WKUserContentController` and the coordinator — mitigated by the coordinator being the `NSViewRepresentable.Coordinator` whose lifecycle is tied to the view; the coordinator holds `weak` references to the router and app state; no `removeScriptMessageHandler` is needed during normal teardown since the coordinator is released when the representable is destroyed.

## Spec Reference
> Extracted from `README.md` — the original entry for this module:

```
Foundation → Text Editor Window → Terminal → Project File Tree → Markdown Preview → PDF Viewer → HTML Preview → Resources

8. HMTL PREVIEW
```

> Module map entry (from `CLAUDE.md`):

```
| 8 | HTML Preview | Live HTML preview, synced to editor |
```

> Related editor spec the preview is driven by:

```
3. EDITOR WINDOW …
  11. HTML language support (Inline Suggestions / Ghost Text, Debouncing)
```
