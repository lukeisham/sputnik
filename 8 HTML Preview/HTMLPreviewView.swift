import AppKit
import SwiftUI
import WebKit

// MARK: - More Context Web View

/// A `WKWebView` subclass that injects "More Context" help items into the right-click menu.
///
/// Overrides `willOpenMenu(_:with:)` to read the current selection from the coordinator
/// and build resolver-driven menu items via `MoreContextMenu.items(...)`. Both HelpTopic
/// kinds relevant to HTML preview — `.grammar` and `.html` — are offered.
private final class MoreContextWebView: WKWebView {

    /// Weak reference to the coordinator so we can read captured selection, resolver, etc.
    /// Weak to avoid a retain cycle (the coordinator already owns the navigation delegate).
    weak var previewCoordinator: HTMLPreviewCoordinator?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        guard let coordinator = previewCoordinator,
            !coordinator.capturedSelection.isEmpty
        else { return }

        let resolver = coordinator.helpContextResolver ?? SputnikHelpContextResolver.shared
        let moreItems = MoreContextMenu.items(
            forSelectedText: coordinator.capturedSelection,
            kinds: [.grammar, .html],
            fullText: coordinator.fullSessionText,
            cursorOffset: 0,
            resolver: resolver,
            onRequest: { [weak coordinator] request in
                coordinator?.onRequestHelp?(request)
            }
        )

        guard !moreItems.isEmpty else { return }
        menu.insertItem(.separator(), at: 0)
        for item in moreItems.reversed() {
            menu.insertItem(item, at: 0)
        }
    }
}

// MARK: - HTMLPreviewView

/// Live HTML preview panel — renders the active `.html` editor tab in a `WKWebView`.
///
/// `HTMLPreviewView` is a pure function of `AppState.activeDocument`: when the active
/// tab changes or its text mutates, the view re-renders automatically via `@Observable`
/// propagation. It owns no document state of its own (SR-1, SR-3).
///
/// **When to show:** The panel renders only when the active session's `fileType == .html`.
/// All other file types (or no open document) show a neutral placeholder; stale HTML
/// from a previously active tab is never displayed.
///
/// **Link navigation** is handled by `HTMLPreviewCoordinator` + `LinkNavigationPolicy`:
/// - In-page `#anchor` → scroll in place (`WKNavigationActionPolicy.allow`)
/// - Local file URL → `InterPanelRouter.open(_:)` → new editor tab
/// - `http(s)` / `target="_blank"` → `NSWorkspace.shared.open(_:)` → system browser
/// - `javascript:` / `data:` / unknown → cancelled and logged
///
/// **AppKit bridge rationale (SW-3):** `WKWebView` has no native SwiftUI equivalent;
/// `NSViewRepresentable` is the correct interop path here.
public struct HTMLPreviewView: NSViewRepresentable {

    // MARK: - Environment

    @Environment(AppState.self) private var appState

    // MARK: - Dependencies

    /// The app's inter-panel router, passed in at construction from the app-assembly layer.
    /// Held weakly inside `HTMLPreviewCoordinator` to avoid retain cycles (SW-2).
    private let router: (any InterPanelRouter)?

    /// Whether link-click navigation is enabled. Toggled from `HTMLPreviewPanel` toolbar.
    private let isLinkNavigationEnabled: Bool

    /// Callback for load failures, surfaced as an error banner in the panel.
    private let onLoadError: ((String) -> Void)?

    /// The shared help-context resolver, passed through to the coordinator.
    private let helpContextResolver: HelpContextResolving

    // MARK: - Init

    /// Creates the HTML preview view.
    /// - Parameters:
    ///   - router:                  The app's `InterPanelRouter` instance.
    ///   - isLinkNavigationEnabled: Whether link clicks open files/URLs. Default `true`.
    ///   - onLoadError:             Optional callback when navigation fails.
    ///   - helpContextResolver:     Resolver for "More Context" right-click help. Defaults to
    ///                              `SputnikHelpContextResolver.shared`.
    public init(
        router: (any InterPanelRouter)? = nil,
        isLinkNavigationEnabled: Bool = true,
        onLoadError: ((String) -> Void)? = nil,
        helpContextResolver: HelpContextResolving = SputnikHelpContextResolver.shared
    ) {
        self.router = router
        self.isLinkNavigationEnabled = isLinkNavigationEnabled
        self.onLoadError = onLoadError
        self.helpContextResolver = helpContextResolver
    }

    // MARK: - NSViewRepresentable

    public func makeCoordinator() -> HTMLPreviewCoordinator {
        let c = HTMLPreviewCoordinator(router: router)
        c.isLinkNavigationEnabled = isLinkNavigationEnabled
        c.onLoadError = onLoadError
        c.helpContextResolver = helpContextResolver
        c.onRequestHelp = { [weak appState] request in
            appState?.requestedHelpTarget = request
        }
        return c
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Disable JavaScript execution for security (ISS-010) — previews are read-only.
        // `allowsContentJavaScript` prevents page JS while still allowing our injected
        // WKUserScript for selection capture to function.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        // Inject a user script that captures selection-change events and posts them to
        // the `selectionChange` message handler on the coordinator. This feeds the
        // "More Context" right-click gesture without requiring full JS execution.
        let selectionScript = WKUserScript(
            source: """
                document.addEventListener('selectionchange', function() {
                    var sel = window.getSelection().toString();
                    window.webkit.messageHandlers.selectionChange.postMessage(sel);
                });
                """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(selectionScript)
        configuration.userContentController.add(context.coordinator, name: "selectionChange")

        let webView = MoreContextWebView(frame: .zero, configuration: configuration)
        webView.previewCoordinator = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        let session = appState.activeDocument

        guard let session, session.fileType == .html else {
            // No active session or wrong type — load a blank placeholder.
            webView.loadHTMLString(placeholderHTML, baseURL: nil)
            context.coordinator.currentBaseURL = nil
            return
        }

        // Resolve the baseURL to the file's directory so relative `src`/`href` resolve.
        let baseURL: URL? = session.url.map { $0.deletingLastPathComponent() }
        context.coordinator.currentBaseURL = baseURL

        // Push the latest toggle + error handler + session state into the coordinator.
        context.coordinator.isLinkNavigationEnabled = isLinkNavigationEnabled
        context.coordinator.onLoadError = onLoadError
        context.coordinator.fullSessionText = session.text

        webView.loadHTMLString(session.text, baseURL: baseURL)
    }

    // MARK: - Placeholder

    /// Minimal HTML shown when no `.html` document is active.
    private var placeholderHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          body {
            margin: 0;
            display: flex;
            align-items: center;
            justify-content: center;
            height: 100vh;
            font-family: -apple-system, sans-serif;
            font-size: 13px;
            color: #888;
            background: #1e1e1e;
          }
        </style>
        </head>
        <body><span>No HTML file open</span></body>
        </html>
        """
    }
}
