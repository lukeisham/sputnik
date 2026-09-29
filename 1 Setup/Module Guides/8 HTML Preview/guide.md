---
module: 8 HTML Preview
status: active
last_updated: 2026-09-28
last_verified: 2026-06-15
open_issues: none
plan: 1 Setup/Plans New/2026-06-15 3+8+9 Add JSON file type support.md
---

## Purpose
Render the active editor tab's HTML (supporting the **HTML Living Standard**) to a live web preview, or display a syntax-coloured read-only JSON viewer when a `.json` file is active. Follows the active document, intercepts link clicks so internal links open as new editor tabs, provides optional editor→preview scroll sync for HTML, and performs flicker-free in-place body updates on content-only HTML changes.

## Diagram

```
  Foundation (2.2)                         Module 8 — HTML/JSON Preview panel
  ┌────────────────────────┐               ┌──────────────────────────────────────┐
  │ AppState               │   observes    │  HTMLPreviewPanel (SwiftUI View)      │
  │  activeDocumentID ─────┼──────────────▶│                                       │
  │  openDocuments[…]      │               │  fileType == .json?                   │
  └────────────────────────┘               │    yes → JSONViewerPanel              │
            ▲                               │           ↳ JSONViewerViewModel       │
            │ writes via router (2.1)       │                ↳ JSONSerialization    │
            │                               │                  (background Task)    │
  ┌────────────────────────┐               │    fileType == .html?                 │
  │ Text Editor (3.x)      │               │    yes → HTMLPreviewView (WKWebView)  │
  │  edits .html/.json ────┼──────────────▶│    else → placeholder                 │
  │  "Render as HTML" ⌃⌘H  │               └──────────────┬────────────────────────┘
  │  "Render as JSON" ⌃⌘J  │                              │ user clicks a link (HTML path)
  └────────────────────────┘                              ▼
                                         ┌──────────────────────────────────────┐
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
| `HTMLPreviewPanel.swift` | Top-level SwiftUI panel view — assembles header bar, toolbar (Fit Width, Link Navigation, Scroll Sync toggle, large-file indicator), and the content area; routes to `JSONViewerPanel` when `fileType == .json`, existing HTML path otherwise; switches to wrong-type placeholder and empty-state placeholder for all other types |
| `HTMLPreviewView.swift` | `NSViewRepresentable` wrapping a single `WKWebView` — owns `WKWebViewConfiguration`, the injected `WKUserScript` for selection capture, `SputnikImageSchemeHandler` registration, F-4 CSS injection, local `<img>` path rewriting, `MoreContextWebView` subclass, and scroll-sync dispatch to coordinator; takes the panel-owned `HTMLPreviewCoordinator` by injection and wires the print / save-as-PDF / save-as-HTML actions once in `makeNSView` onto it (ISS-095) |
| `HTMLPreviewCoordinator.swift` | The `NSViewRepresentable.Coordinator` — conforms to `WKNavigationDelegate` and `WKScriptMessageHandler`; holds weak references to router and web view; owns `RenderThrottle` for debounced re-renders; `throttledLoad` performs structural-change detection (in-place body update vs full reload); `syncScrollToFraction(_:)` scrolls via `evaluateJavaScript` |
| `JSONViewerPanel.swift` | SwiftUI view for `.json` files — header bar ("JSON VIEWER" + filename + Copy button + Prettify/Minify toggle), optional parse-error banner, empty-state placeholder, and a read-only `NSTextView` (via `JSONTextViewRepresentable`) showing syntax-coloured output from `JSONViewerViewModel` |
| `JSONViewerViewModel.swift` | `@MainActor @Observable` view-model for the JSON viewer — accepts `rawText`, runs `JSONSerialization` on `Task(priority: .utility)`, pretty-prints or minifies, builds a syntax-coloured `NSAttributedString` (same colour scheme as `SyntaxHighlighter.jsonAttributes()`), publishes `renderedContent` and `lastError`; cancelled and replaced on every text change |
| `LinkNavigationPolicy.swift` | Pure function enum — classifies a URL as `.allowInPage`, `.openAsTab(URL)`, `.openExternally(URL)`, or `.block`; no WebKit types in its signature, unit-testable in isolation |
| `SputnikImageSchemeHandler.swift` | `WKURLSchemeHandler` for the custom `sputnik-img://` scheme — decodes percent-encoded paths, resolves against the coordinator's base directory, streams downsampled image bytes via `PreviewImageResolver`; serves a 1×1 transparent placeholder for missing/oversized images |
| `Package.swift` | SPM manifest — declares dependencies on `FoundationModule`, `ResourcesModule` |
| `Tests/HTMLPreviewModuleTests.swift` | Unit tests — covers `LinkNavigationPolicy` decisions (happy path, edge cases, error conditions) and `HTMLPreviewCoordinator` state transitions |

## Technical Summary
- **Framework(s):** WebKit (`WKWebView`, `WKNavigationDelegate`), SwiftUI (`NSViewRepresentable`), AppKit, Foundation (`JSONSerialization`). Target HTML rendering is the **HTML Living Standard** (WebKit/Safari).
- **Key types:**
  - `HTMLPreviewPanel` — top-level `View` that assembles the header, toolbar (Fit Width + Link Navigation toggle), and content area; observes `AppState.activeDocument` via `@Environment`; routes `fileType == .json` to `JSONViewerPanel`, `fileType == .html` to the existing `HTMLPreviewView` path, and all other types to a placeholder
  - `HTMLPreviewView` — `NSViewRepresentable` wrapping a single `WKWebView`; observes `AppState.activeDocument` and re-renders when the active document changes or its text mutates (SW-3: AppKit bridge is justified because `WKWebView` has no SwiftUI equivalent); owns F-4 CSS injection and local `<img>` path rewriting (private methods `htmlByInjectingOverrides` and `rewriteLocalImageSources`)
  - `HTMLPreviewCoordinator` — the `NSViewRepresentable.Coordinator`; conforms to `WKNavigationDelegate` and `WKScriptMessageHandler`; holds a `weak` reference to the router; uses `RenderThrottle` (2.7) to debounce rapid re-renders; `throttledLoad(html:baseURL:)` calls `splitHTML` to compare the `<head>` section — on content-only changes (same head/CSS + same baseURL), calls `updateBodyInPlace(_:)` via `evaluateJavaScript` to update `document.body.innerHTML` without a full reload (ISS-062/064); on structural changes, calls `loadHTMLString`; `isBaseLoaded: Bool` prevents body injection before a document exists; `syncScrollToFraction(_:)` applies JS `window.scrollTo` guarded by `lastSyncScrollFraction` delta (ISS-063); the `throttle` closure is `@MainActor` — no inner `Task { @MainActor in }` hop is needed, so the body update fires in the same run-loop cycle as the throttle expiry (ISS-084)
  - `MoreContextWebView` — private `WKWebView` subclass inside `HTMLPreviewView.swift` that overrides `willOpenMenu(_:with:)` to inject "More Context: Style Guide" and "More Context: HTML Help" items into the right-click context menu via the shared `MoreContextMenu.items(...)` builder (2.7); reads `capturedSelection` from the coordinator (populated by the `selectionchange` script message)
  - `LinkNavigationPolicy` — pure function `decide(for: URL, targetIsBlank: Bool, currentBaseURL: URL?) -> Decision` returning `.allowInPage` / `.openAsTab(URL)` / `.openExternally(URL)` / `.block`; unit-testable in isolation, no WebKit types in its signature
  - `SputnikImageSchemeHandler` — `WKURLSchemeHandler` for the custom `sputnik-img://` scheme; streams downsampled image bytes (or a 1×1 transparent placeholder for missing/oversized images); never grants broad file sandbox access (ISS-047)
  - `JSONViewerPanel` — SwiftUI view for `.json` files; owns a `@State private var viewModel = JSONViewerViewModel()`; header bar with Prettify/Minify toggle and Copy button; error banner when `viewModel.lastError != nil`; empty-state placeholder for empty documents; `JSONTextViewRepresentable` (private `NSViewRepresentable` inside the same file) hosts a read-only `NSTextView` displaying `viewModel.renderedContent`; no toolbar (JSON viewer has no Fit Width or sync options)
  - `JSONViewerViewModel` — `@MainActor @Observable`; `rawText: String { didSet { scheduleRender() } }` — cancels the previous `Task` and starts a new `Task.detached(priority: .utility)` that calls `JSONSerialization.jsonObject`, then re-serializes to pretty or minified form, then calls `colorize(_:)` to build an `NSAttributedString`; `displayMode: DisplayMode` (.pretty / .minified); `toggleDisplayMode()` flips mode and re-renders; `lastError: String?` captures the `localizedDescription` on parse failure; never imports Module 3 directly (SR-1)
  - Consumes Foundation types only: `DocumentSession` and `activeDocumentID` (2.2), `InterPanelRouter` (2.1), `FileType` (2.1), `MoreContextMenu` (2.7), `HelpContextResolving` (2.7) — this module owns no document state of its own (SR-1)
- **Threading model:** All `WKWebView` calls and the HTML render path are `@MainActor`. For the JSON viewer, `JSONSerialization` parsing and `NSAttributedString` assembly run on `Task.detached(priority: .utility)`; only the `renderedContent` write hops back to `@MainActor`. Re-render is triggered by observing `activeDocumentID` and the active session's text; rapid HTML re-renders are coalesced by `HTMLPreviewCoordinator`'s own `RenderThrottle` (`throttledLoad`). JSON re-renders cancel the previous task on each text change.
- **F-4 (Per-panel font/background):** `HTMLPreviewView.htmlByInjectingOverrides(...)` wraps the user's HTML with a `<style>` block that overrides `body background-color` and base `font-family`/`font-size` using `settings.resolvedHtmlPreviewFont` and `settings.htmlPreviewBackground`; resolved font falls back to `editorFont` when no per-panel override is set. Background colour is not persisted (in-memory only via `Color` value).
- **CSS-injection cache (ISS-085):** `htmlByInjectingOverrides` is O(n) (regex `<img>` rewriting + string assembly) and previously ran on every `updateNSView` call — including every scroll tick when sync is on. `updateNSView` now computes `inputHash = session.text.hashValue ^ hash(font postscript name + point size + htmlPreviewBackground)` and only re-runs the injection when the hash changes; otherwise it reuses `coordinator.lastStyledHTML`. The per-scroll hot path is reduced to a single integer comparison. **Cache-coherence rule:** every `SettingsStore` property read inside `htmlByInjectingOverrides` must also be folded into `inputHash`, or the cache will serve stale CSS (a comment on the function lists the current inputs).
- **Data flow:**
  - *Render (flicker-free, ISS-062/064):* `activeDocumentID` changes or active `.html` text mutates → `HTMLPreviewView.updateNSView` → `htmlByInjectingOverrides(...)` injects F-4 CSS + rewrites local `<img>` paths → `coordinator.throttledLoad(html:baseURL:)`. `throttledLoad` calls `splitHTML` to split at `</head>`: if the `<head>` section is unchanged and the `baseURL` is the same, calls `updateBodyInPlace(_:)` (injects body via `document.body.innerHTML = <json>` using `evaluateJavaScript` — preserves scroll and selection); otherwise calls `loadHTMLString` (first load, CSS settings changed, or different file). `isBaseLoaded` gates body injection on a successful `didFinish` navigation.
  - *Scroll sync (ISS-063):* `HTMLPreviewView` accepts `syncScrollEnabled: Bool`; when true, reads `appState.editorScrollFraction` in `updateNSView` (causing SwiftUI to observe it) and calls `coordinator.syncScrollToFraction(_:)`. `syncScrollToFraction` injects JS `window.scrollTo(0, h * fraction)` guarded by `lastSyncScrollFraction` delta > 0.005. Disabled when `isLargeFile` (>80k chars); "Large file — sync limited" shown in toolbar.
  - *Security:* `configuration.defaultWebpagePreferences.allowsContentJavaScript = false` (ISS-010) — disables author-injected JS while allowing the app's own `WKUserScript` for selection capture; replaces the previous `javaScriptEnabled = false` which blocked both
  - *Selection capture:* A `WKUserScript` injected at `atDocumentEnd` listens for `selectionchange` events and posts the selected text via `window.webkit.messageHandlers.selectionChange.postMessage(...)`; the coordinator's `WKScriptMessageHandler.didReceive(_:)` stores the selection in `capturedSelection` — this is read synchronously by `MoreContextWebView.willOpenMenu(_:with:)` (since `willOpenMenu` is synchronous and cannot query the web view directly)
  - *More Context:* `MoreContextWebView.willOpenMenu(_:with:)` inserts two items at the top of the right-click menu: "More Context: Style Guide" (`.style` kind) and "More Context: HTML Help" (`.html` kind), using the cached `capturedSelection` and the shared resolver; the `onRequest` sink writes the resolved `HelpRequest` to `AppState.requestedHelpTarget`
  - *Sync:* the preview never tracks a file URL directly — it renders **whatever document is active**. Switching editor tabs switches the preview with no extra binding (see Failure modes / SR-1). This is the answer to "which preview syncs to which editor": there is one active document, and the preview is a pure function of it.
  - *Link click:* `WKNavigationDelegate.webView(_:decidePolicyFor:decisionHandler:)` → `LinkNavigationPolicy.decide(…)` → in-page `#anchor` scrolls in place (`.allow`); internal local files (`.html`, `.md`, `.pdf`, and other Sputnik-compatible types) are opened as **new editor tabs** within the app via `InterPanelRouter.open(url)` (`.cancel` + route to Foundation 2.1); external `http(s)` URLs or `target="_blank"` links are opened in the user's **default web browser** via `NSWorkspace.shared.open(url)` (`.cancel`).
- **State owned:** None persistent. Holds only the live `WKWebView` instance and its coordinator; the document text and active-tab identity are owned by Foundation `AppState` (2.2). This keeps the panel disposable and low-RAM (SR-3) — closing the panel releases the web view.
- **Dependencies:** Foundation 2.2 (`AppState.activeDocumentID`, `DocumentSession`); Foundation 2.1 (`InterPanelRouter.open(_:)`, `FileType`); Text Editor 3.4 (source of `.html` text + the "Render as HTML" command); Foundation 2.4 (placeholder/empty-state styling, `SputnikAlert` for load errors); Foundation 2.7 (`MoreContextMenu`, `HelpContextResolving`, `HelpContextQuery`).
- **Failure modes:**
  - Active document is not `.html` → panel shows a neutral placeholder; it does **not** render stale content from a previously active tab. The placeholder is loaded **once** and guarded by `coordinator.isShowingPlaceholder` so unrelated `AppState` changes (e.g. focus switches) no longer reload/reflash it (ISS-092); the flag is reset to `false` whenever a real `.html` session is loaded.
  - Head-only HTML (a document ending at `</head>` with no body) is split safely by `splitHTML` — the head/body split uses a half-open range that no longer traps when `</head>` ends the string (ISS-086).
  - **AppKit-bridge containment (ISS-095):** the print / save-as-PDF / save-as-HTML closures are wired **once** in `HTMLPreviewView.makeNSView` onto the panel-owned `HTMLPreviewCoordinator`, not rebuilt on every `updateNSView` pass. `HTMLPreviewPanel` creates the coordinator in its `init`, injects it into `HTMLPreviewView`, reads the actions off it for the overflow menu, and registers paired-preview actions as coordinator-delegating closures. The closures read the coordinator's live `currentBaseURL` / `fullSessionText` at call time so they always reflect the active document.
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
- `WKUserScript` for selection capture is the **only** externally-injected script at configuration time — `allowsContentJavaScript = false` prevents page-authored scripts (ISS-010); `evaluateJavaScript` (used for body update and scroll sync) is app-injected and is not blocked by `allowsContentJavaScript`
- Local `<img src>` paths are rewritten to `sputnik-img://` at render-time — `SputnikImageSchemeHandler` is the only path for local image bytes, never direct `file://` access (ISS-047, SR-3)
- The panel routes `fileType == .json` to `JSONViewerPanel` and `fileType == .html` to the `HTMLPreviewView` path — stale HTML is never displayed when a JSON file is active, and vice versa
- `JSONViewerViewModel` never imports Module 3 (`SyntaxHighlighter`) — it reimplements the colour scheme inline in `colorize(_:)` so the two modules remain independent (SR-1)
- `AppState.pairedPreviewPrintAction` and `AppState.pairedPreviewSaveAsPDFAction` are set to the live print/PDF closures when a `.html` document is active; cleared for `.json`, other types, no active document, or `.onDisappear` — JSON has no paired print/PDF action

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
