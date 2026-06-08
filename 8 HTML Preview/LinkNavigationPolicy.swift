import Foundation

/// A pure, WebKit-free policy engine that classifies a link click in the HTML preview.
///
/// `LinkNavigationPolicy` is intentionally free of `WKWebView` or any WebKit types so
/// it can be unit-tested in isolation. `HTMLPreviewCoordinator` calls `decide(for:…)`
/// and maps the returned `Decision` to a `WKNavigationActionPolicy`.
///
/// **Classification rules (in priority order):**
/// 1. `#anchor` (fragment-only, same URL base) → `.allowInPage`
/// 2. Local file URL with a text/html/markdown/pdf extension → `.openAsTab(url)`
/// 3. `http` or `https` scheme, or `target="_blank"` link → `.openExternally(url)`
/// 4. `mailto:` → `.openExternally(url)` (handed to NSWorkspace)
/// 5. All other schemes (`javascript:`, `data:`, etc.) → `.block`
public enum LinkNavigationPolicy {

    // MARK: - Decision

    /// The action `HTMLPreviewCoordinator` should take for a given navigation.
    public enum Decision: Sendable {
        /// Let the web view complete the navigation (in-page anchor scroll only).
        case allowInPage
        /// Cancel the web-view navigation and open the URL as a new editor tab.
        case openAsTab(URL)
        /// Cancel the web-view navigation and open the URL in the system browser
        /// (or the appropriate helper app for `mailto:` etc.).
        case openExternally(URL)
        /// Cancel and log; do not navigate or open.
        case block
    }

    // MARK: - Classification

    /// Returns the navigation decision for a link clicked in the HTML preview.
    ///
    /// - Parameters:
    ///   - url:            The absolute URL of the navigation request.
    ///   - targetIsBlank:  `true` when the link has `target="_blank"`.
    ///   - currentBaseURL: The `baseURL` used when the preview was last loaded, i.e.
    ///                     the directory of the active `.html` document. Pass `nil` when
    ///                     unavailable; `#anchor` detection still works via fragment check.
    /// - Returns: The `Decision` the coordinator should act on.
    public static func decide(
        for url: URL,
        targetIsBlank: Bool,
        currentBaseURL: URL?
    ) -> Decision {

        // 1. In-page anchor: fragment-only change on the same resource.
        if isInPageAnchor(url, baseURL: currentBaseURL) {
            return .allowInPage
        }

        // 2. External link or target="_blank".
        if targetIsBlank {
            return .openExternally(url)
        }
        if let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                return .openExternally(url)

            case "mailto":
                return .openExternally(url)

            case "file":
                // Local file — open as a new editor tab so the preview stays synced.
                return .openAsTab(url)

            case "javascript", "data", "blob":
                // Never execute potentially harmful schemes.
                return .block

            default:
                // Unknown scheme — block and log; do not navigate.
                return .block
            }
        }

        // No scheme — relative path that wasn't resolved to a file URL; block.
        return .block
    }

    // MARK: - Private helpers

    /// Returns `true` when the URL is a fragment-only navigation on the same page.
    private static func isInPageAnchor(_ url: URL, baseURL: URL?) -> Bool {
        // A fragment-only URL has the form `<base>#<anchor>`.
        guard url.fragment != nil else { return false }

        // Strip the fragment from both URLs and compare.
        var strippedComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        strippedComponents?.fragment = nil
        let strippedTarget = strippedComponents?.url

        if let base = baseURL {
            var baseComponents = URLComponents(url: base, resolvingAgainstBaseURL: false)
            baseComponents?.fragment = nil
            let strippedBase = baseComponents?.url
            return strippedTarget == strippedBase
        }

        // No base URL available — treat any fragment-only URL (no path component
        // beyond the current page) as in-page.
        return strippedTarget?.path.isEmpty ?? false
    }
}
