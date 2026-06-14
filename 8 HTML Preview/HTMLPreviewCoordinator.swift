import AppKit
import FoundationModule
import WebKit

/// The `NSViewRepresentable.Coordinator` for `HTMLPreviewView`.
///
/// Owns the `WKNavigationDelegate` implementation and translates `WKWebView` navigation
/// callbacks into `LinkNavigationPolicy.Decision` actions. The coordinator holds a
/// **weak** reference to the router so it never forms a retain cycle (SW-2).
///
/// **Threading:** All `WKNavigationDelegate` callbacks arrive on the main thread; the
/// coordinator is `@MainActor` so calling `InterPanelRouter` methods (also `@MainActor`)
/// requires no actor hop.
@MainActor
public final class HTMLPreviewCoordinator: NSObject, WKNavigationDelegate {

    // MARK: - Properties

    /// The base URL of the document currently rendered in the web view; updated by
    /// `HTMLPreviewView.updateNSView` each time the active session changes.
    /// Used by `LinkNavigationPolicy` to detect in-page anchor navigations.
    var currentBaseURL: URL?

    /// Weak reference to the router — avoids a retain cycle between coordinator,
    /// web view, and the app-level router singleton (SW-2).
    weak var router: (any InterPanelRouter)?

    /// When `false`, all link clicks are suppressed — the preview becomes read-only.
    /// Toggled by the `[🔗]` button in `HTMLPreviewPanel`.
    var isLinkNavigationEnabled: Bool = true

    /// Called when a navigation fails; the panel can surface this as an error banner.
    var onLoadError: ((String) -> Void)?

    /// The most recently captured selection text from the WKWebView.
    var capturedSelection: String = ""

    /// The full text of the HTML session (for context).
    var fullSessionText: String = ""

    /// Closure invoked when the user selects "More Context" to request a help panel.
    var onRequestHelp: ((HelpRequest?) -> Void)?

    /// The shared help-context resolver.
    var helpContextResolver: HelpContextResolving?

    /// Weak reference to the web view, set by `HTMLPreviewView.updateNSView`.
    weak var webView: WKWebView?

    /// Closure that prints the web view content. Set by `HTMLPreviewView.updateNSView`.
    var printAction: (() -> Void)?

    /// Closure that saves the web view content as a PDF. Set by `HTMLPreviewView.updateNSView`.
    var saveAsPDFAction: (() -> Void)?

    /// Closure that saves the raw HTML source text as a `.html` file. Set by `HTMLPreviewView.updateNSView`.
    var saveAsHTMLAction: (() -> Void)?

    /// Throttles rapid re-renders during fast HTML edits (SR-4).
    let renderThrottle = RenderThrottle()

    // MARK: - In-place HTML update (ISS-062, Steps 2 & 7)

    /// `<head>…</head>` section of the last full-page load. If unchanged on the next render,
    /// only the body is updated via `evaluateJavaScript`, avoiding a full-page reload and the
    /// scroll-to-top flicker it causes (Step 2).
    var lastFullLoadHead: String = ""

    /// Base URL used in the last full-page load. A changed base URL triggers a full reload.
    var lastFullLoadBaseURL: URL? = nil

    /// `true` after the first successful `loadHTMLString` navigation. Guards against injecting
    /// body HTML before a document exists (which would silently fail).
    var isBaseLoaded: Bool = false

    // MARK: - Placeholder reload guard (ISS-092)

    /// `true` while the blank placeholder web view is the current content. Guards
    /// `HTMLPreviewView.updateNSView` against reloading the placeholder on every
    /// AppState change (which caused a visible reflash on focus switches). Reset to
    /// `false` whenever a real HTML session is loaded.
    var isShowingPlaceholder: Bool = false

    // MARK: - CSS-injection cache (ISS-085)

    /// The last result of `htmlByInjectingOverrides`, reused on the scroll-sync hot path.
    var lastStyledHTML: String = ""

    /// Hash of the inputs that produced `lastStyledHTML` (session text + CSS-affecting
    /// settings). When unchanged, the O(n) CSS injection is skipped and `lastStyledHTML`
    /// is reused — reducing the per-scroll cost to a single integer comparison.
    var lastStyledInputHash: Int = 0

    // MARK: - Preview scroll sync (ISS-063, Steps 3 & 5)

    /// Last fractional scroll position applied by editor→preview sync.
    /// Guards against feedback loops — only scrolls when the fraction shifts >0.005.
    var lastSyncScrollFraction: Double = -1

    // MARK: - Throttled load (adaptive, flicker-free)

    /// Throttled HTML load with structural-change detection (Steps 2 & 7).
    /// When only the `<body>` content changed (head/CSS unchanged, same baseURL),
    /// uses `evaluateJavaScript` to update `document.body.innerHTML` in place,
    /// preserving the current scroll position. Falls back to a full `loadHTMLString`
    /// when structure changes (different CSS settings, new baseURL, or first load).
    func throttledLoad(html: String, baseURL: URL?) {
        currentBaseURL = baseURL
        // throttle's render closure executes on @MainActor — no inner Task hop needed (ISS-084).
        renderThrottle.throttle { [weak self] in
            guard let self else { return }
            let (head, bodyContent) = Self.splitHTML(html)
            if self.isBaseLoaded,
                head == self.lastFullLoadHead,
                baseURL == self.lastFullLoadBaseURL
            {
                // Content-only change — update body in place (Step 2).
                await self.updateBodyInPlace(bodyContent)
            } else {
                // Structural change or first load — full reload.
                self.lastFullLoadHead = head
                self.lastFullLoadBaseURL = baseURL
                self.isBaseLoaded = false
                self.lastSyncScrollFraction = -1
                self.webView?.loadHTMLString(html, baseURL: baseURL)
            }
        }
    }

    // MARK: - Scroll sync

    /// Scrolls the WKWebView to the given fractional position (0 = top, 1 = bottom).
    /// No-op if the fraction hasn't changed by more than 0.005 since last application.
    func syncScrollToFraction(_ fraction: Double) {
        guard abs(fraction - lastSyncScrollFraction) > 0.005 else { return }
        lastSyncScrollFraction = fraction
        let js = """
            (function(){
                var h = document.documentElement.scrollHeight
                      - document.documentElement.clientHeight;
                if (h > 0) window.scrollTo(0, Math.round(h * \(fraction)));
            })();
            """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Helpers

    /// Splits a fully-assembled HTML string into the `<head>` section (up to and including
    /// `</head>`) and the body's inner HTML (the content between `<body>` and `</body>`).
    /// Used to detect structural vs content-only changes for in-place updates.
    static func splitHTML(_ html: String) -> (head: String, bodyContent: String) {
        guard let headEndRange = html.range(of: "</head>", options: .caseInsensitive) else {
            return ("", html)
        }
        // Half-open range: a closed `...upperBound` traps when `upperBound == endIndex`
        // (head-only HTML with no body — ISS-086). The half-open form yields the head
        // including `</head>` and is safe at the end of the string.
        let head = String(html[html.startIndex..<headEndRange.upperBound])
        let afterHead = String(html[headEndRange.upperBound...])

        let bodyTagPattern = #"<body[^>]*>"#
        if let regex = try? NSRegularExpression(pattern: bodyTagPattern, options: .caseInsensitive),
            let match = regex.firstMatch(
                in: afterHead, range: NSRange(afterHead.startIndex..., in: afterHead)),
            let bodyTagRange = Range(match.range, in: afterHead)
        {
            let afterBodyTag = String(afterHead[bodyTagRange.upperBound...])
            if let bodyEndRange = afterBodyTag.range(of: "</body>", options: .caseInsensitive) {
                return (
                    head, String(afterBodyTag[afterBodyTag.startIndex..<bodyEndRange.lowerBound])
                )
            }
            return (head, afterBodyTag)
        }
        return (head, afterHead)
    }

    /// Replaces the live document's `body.innerHTML` via JavaScript without a full page reload,
    /// preserving the current scroll position. JSON-encodes the content for safe JS embedding.
    @MainActor
    private func updateBodyInPlace(_ bodyContent: String) async {
        guard let data = try? JSONEncoder().encode(bodyContent),
            let json = String(data: data, encoding: .utf8)
        else { return }
        _ = try? await webView?.evaluateJavaScript("document.body.innerHTML = \(json);")
    }

    // MARK: - Init

    /// Creates the coordinator.
    /// - Parameter router: The app's concrete `InterPanelRouter` instance, held weakly.
    public init(router: (any InterPanelRouter)?) {
        self.router = router
    }

    // MARK: - WKNavigationDelegate

    /// Intercepts every navigation in the preview and applies `LinkNavigationPolicy`.
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Initial `loadHTMLString` call arrives as `.other` navigation type; allow it.
        if navigationAction.navigationType == .other {
            decisionHandler(.allow)
            return
        }

        // When link navigation is disabled, cancel all user-initiated navigations.
        guard isLinkNavigationEnabled else {
            decisionHandler(.cancel)
            return
        }

        let targetIsBlank = navigationAction.targetFrame == nil
        let decision = LinkNavigationPolicy.decide(
            for: url,
            targetIsBlank: targetIsBlank,
            currentBaseURL: currentBaseURL
        )

        switch decision {
        case .allowInPage:
            decisionHandler(.allow)

        case .openAsTab(let fileURL):
            decisionHandler(.cancel)
            Task { [weak self] in
                await self?.router?.open(fileURL)
            }

        case .openExternally(let externalURL):
            decisionHandler(.cancel)
            NSWorkspace.shared.open(externalURL)

        case .block:
            decisionHandler(.cancel)
            // Log to console in debug builds only.
            #if DEBUG
                print("[HTMLPreview] Blocked navigation to \(url.absoluteString)")
            #endif
        }
    }

    /// Marks the base document as loaded after a successful full-page navigation,
    /// enabling subsequent in-place body updates (Step 2).
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isBaseLoaded = true
    }

    /// Logs navigation failures and surfaces the error to the panel for UI display.
    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation,
        withError error: any Error
    ) {
        onLoadError?(error.localizedDescription)
        #if DEBUG
            print("[HTMLPreview] Navigation failed: \(error.localizedDescription)")
        #endif
    }

    /// Logs provisional navigation failures (e.g. DNS / network errors before a page loads).
    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation,
        withError error: any Error
    ) {
        onLoadError?(error.localizedDescription)
        #if DEBUG
            print("[HTMLPreview] Provisional navigation failed: \(error.localizedDescription)")
        #endif
    }
}

// MARK: - WKScriptMessageHandler

extension HTMLPreviewCoordinator: WKScriptMessageHandler {

    /// Receives selection-change messages from the injected WKUserScript.
    /// Updates `capturedSelection` on every `selectionchange` event in the WKWebView.
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "selectionChange",
            let selection = message.body as? String
        else { return }
        capturedSelection = selection
    }
}
