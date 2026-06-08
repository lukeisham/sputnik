import AppKit
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
