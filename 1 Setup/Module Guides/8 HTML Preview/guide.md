---
module: 8 HTML Preview
status: stable
last_updated: 2026-06-12
last_verified: 2026-06-12
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

## Source Files
| File | Responsibility |
|---|---|
| `HTMLPreviewPanel.swift` | Top-level SwiftUI panel view — assembles header bar, toolbar (Fit Width + Link Navigation toggle), and the content area; switches between rendering, wrong-type placeholder, and empty-state placeholder based on `AppState.activeDocument` |
| `HTMLPreviewView.swift` | `NSViewRepresentable` wrapping a single `WKWebView` — owns `WKWebViewConfiguration`, the injected `WKUserScript` for selection capture, `SputnikImageSchemeHandler` registration, F-4 CSS injection, local `<img>` path rewriting, and the `MoreContextWebView` subclass that injects "More Context" menu items |
| `HTMLPreviewCoordinator.swift` | The `NSViewRepresentable.Coordinator` — conforms to `WKNavigationDelegate` (link navigation policy) and `WKScriptMessageHandler` (selection capture); holds weak references to the router and web view; owns the `RenderThrottle` for debounced re-renders |
| `LinkNavigationPolicy.swift` | Pure function enum — classifies a URL as `.allowInPage`, `.openAsTab(URL)`, `.openExternally(URL)`, or `.block`; no WebKit types in its signature, unit-testable in isolation |
| `SputnikImageSchemeHandler.swift` | `WKURLSchemeHandler` for the custom `sputnik-img://` scheme — decodes percent-encoded paths, resolves against the coordinator's base directory, streams downsampled image bytes via `PreviewImageResolver`; serves a 1×1 transparent placeholder for missing/oversized images |
| `Package.swift` | SPM manifest — declares dependencies on `FoundationModule`, `ResourcesModule`, `SputnikShared` |
| `Tests/HTMLPreviewModuleTests.swift` | Unit tests — covers `LinkNavigationPolicy` decisions (happy path, edge cases, error conditions) and `HTMLPreviewCoordinator` state transitions |

## Technical Summary
- **Framework(s):** WebKit (`WKWebView`, `WKNavigationDelegate`), SwiftUI (`NSViewRepresentable`), AppKit. Target rendering is the **HTML Living Standard** (WebKit/Safari).
- **Key types:**
  - `HTMLPreviewPanel` — top-level `View` that assembles the header, toolbar (Fit Width + Link Navigation toggle), and content area; observes `AppState.activeDocument` via `@Environment` and switches between rendering (`.html`), wrong-type placeholder, and empty-state placeholder
  - `HTMLPreviewView` — `NSViewRepresentable` wrapping a single `WKWebView`; observes `AppState.activeDocument` and re-renders when the active document changes or its text mutates (SW-3: AppKit bridge is justified because `WKWebView` has no SwiftUI equivalent); owns F-4 CSS injection and local `<img>` path rewriting (private methods `htmlByInjectingOverrides` and `rewriteLocalImageSources`)
  - `HTMLPreviewCoordinator` — the `NSViewRepresentable.Coordinator`; conforms to `WKNavigationDelegate` and owns the link-navigation policy; also conforms to `WKScriptMessageHandler` to receive selection-change messages from the injected script; holds a `weak` reference to the router, never a strong `self` capture in delegate callbacks (SW-2); uses `RenderThrottle` (2.7) to debounce rapid keystroke-triggered re-renders
  - `MoreContextWebView` — private `WKWebView` subclass inside `HTMLPreviewView.swift` that overrides `willOpenMenu(_:with:)` to inject "More Context: Grammar Help" and "More Context: HTML Help" items into the right-click context menu via the shared `MoreContextMenu.items(...)` builder (2.7); reads `capturedSelection` from the coordinator (populated by the `selectionchange` script message)
  - `LinkNavigationPolicy` — pure function `decide(for: URL, targetIsBlank: Bool, currentBaseURL: URL?) -> Decision` returning `.allowInPage` / `.openAsTab(URL)` / `.openExternally(URL)` / `.block`; unit-testable in isolation, no WebKit types in its signature
  - `SputnikImageSchemeHandler` — `WKURLSchemeHandler` for the custom `sputnik-img://` scheme; streams downsampled image bytes (or a 1×1 transparent placeholder for missing/oversized images); never grants broad file sandbox access (ISS-047)
  - Consumes Foundation types only: `DocumentSession` and `activeDocumentID` (2.2), `InterPanelRouter` (2.1), `FileType` (2.1), `MoreContextMenu` (2.7), `HelpContextResolving` (2.7) — this module owns no document state of its own (SR-1)
- **Threading model:** All `WKWebView` calls and the render path are `@MainActor`. Re-render is triggered by observing `activeDocumentID` and the active session's debounced text (debounce lives in 3.4, not here). HTML string assembly is trivial and stays on the main thread; no background Task is needed for preview itself.
- **F-4 (Per-panel font/background):** `HTMLPreviewView.htmlByInjectingOverrides(...)` wraps the user's HTML with a `<style>` block that overrides `body background-color` and base `font-family`/`font-size` using `settings.resolvedHtmlPreviewFont` and `settings.htmlPreviewBackground`; resolved font falls back to `editorFont` when no per-panel override is set. Background colour is not persisted (in-memory only via `Color` value).
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
  - **Image display (ISS-047):** Local `<img src="…">` references in the HTML are rewritten during preprocessing to use a custom `sputnik-img://` scheme: the `HTMLPreviewView.htmlByInjectingOverrides(…)` function finds all `<img src="…">` whose value is a relative or local path, and rewrites it to `src="sputnik-img://host/…"` (the path is percent-encoded). The `WKURLSchemeHandler`-conforming `SputnikImageSchemeHandler` is registered for this scheme; when invoked, it parses the path, calls `PreviewImageResolver.data(relativeTo:baseDir)`, and responds with the downsampled bytes (or a 1×1 transparent placeholder for missing/oversized images). This avoids granting broad file sandbox access and keeps the HTML string bounded. Remote `http(s)` and existing `data:` URIs are left untouched. The 2000 px and 20 MB limits are enforced in the shared resolver (module 9.6) — same limit applies to Markdown and PDF (SR-1, SR-3).
  - Very large HTML string → rendering is bounded by the editor's existing file-size guard (module 3 spec, SR-3); module 8 adds no second copy of the text — it reads the active session's buffer.
  - Web content tries to navigate the top frame on its own (meta refresh, script) → treated like any navigation: same `LinkNavigationPolicy` applies, so it cannot silently desync the preview from the editor.
  - `WKScriptMessageHandler` registration creates a potential retain cycle between `WKUserContentController` and the coordinator — mitigated by the coordinator being the `NSViewRepresentable.Coordinator` whose lifecycle is tied to the view; the coordinator holds `weak` references to the router and app state; no `removeScriptMessageHandler` is needed during normal teardown since the coordinator is released when the representable is destroyed.

## Invariants
- This panel **observes** `AppState.activeDocument` — it never writes to `AppState.documentSessions` or calls `openDocument`/`closeDocument` directly; all file-open actions are routed through `InterPanelRouter.open(_:)` (SR-1)
- All `WKWebView` calls and navigation delegate callbacks happen on `@MainActor` — never called from a background queue (SW-1)
- `LinkNavigationPolicy` is the **only** URL classifier in the module — no inline URL-scheme checks in the coordinator or view code
- The coordinator holds **weak** references to both the router and web view — never a strong capture in delegate callbacks or closures (SW-2)
- `MoreContextWebView` references the coordinator weakly — never forms a retain cycle through the menu item closure chain
- `WKUserScript` for selection capture is the **only** script injected — `allowsContentJavaScript = false` prevents page-authored scripts (ISS-010)
- Local `<img src>` paths are rewritten to `sputnik-img://` at render-time — `SputnikImageSchemeHandler` is the only path for local image bytes, never direct `file://` access (ISS-047, SR-3)
- The panel renders **only** when the active session's `fileType == .html` — stale HTML from a previously active tab is never displayed

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
