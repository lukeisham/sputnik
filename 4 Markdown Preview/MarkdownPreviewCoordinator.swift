import AppKit

/// The `NSViewRepresentable.Coordinator` for `MarkdownRenderView`.
///
/// Conforms to `NSTextViewDelegate` and intercepts link clicks on the rendered
/// Markdown. Link routing mirrors the philosophy of `LinkNavigationPolicy` (module 8):
/// local `file://` URLs → `InterPanelRouter.open(_:)` → new editor tab;
/// `http(s)` / `mailto:` → `NSWorkspace.shared.open(_:)` → system handler;
/// unsafe schemes (`javascript:`, `data:`) → blocked and logged.
///
/// **Threading:** All `NSTextViewDelegate` callbacks arrive on the main thread.
/// The router methods are `@MainActor` — no actor hop is required.
@MainActor
public final class MarkdownPreviewCoordinator: NSObject, NSTextViewDelegate {

    // MARK: - Properties

    /// Weak reference to the app's inter-panel router. Held weakly to avoid
    /// retain cycles between the coordinator, the text view, and the router (SW-2).
    /// When `nil`, all link clicks are silently ignored (links become selection-only).
    public weak var router: (any InterPanelRouter)?

    /// When `false`, link-click handling is disabled entirely and all clicks
    /// become selection-only gestures. Toggled from the panel toolbar.
    public var linksEnabled: Bool = true

    // MARK: - Init

    /// Creates the coordinator.
    /// - Parameter router: The app's concrete `InterPanelRouter` instance, held weakly.
    public init(router: (any InterPanelRouter)?) {
        self.router = router
    }

    // MARK: - NSTextViewDelegate

    /// Intercepts every link click in the preview and routes it safely.
    ///
    /// - Parameters:
    ///   - textView:   The text view that received the click.
    ///   - link:       The link value. May be `URL`, `NSURL`, or `String`.
    ///   - charIndex:  The character index where the link was clicked.
    /// - Returns: `true` if the click was handled (including blocking unsafe links);
    ///   `false` to let the system handle it as a default.
    public func textView(
        _ textView: NSTextView,
        clickedOnLink link: Any,
        at charIndex: Int
    ) -> Bool {
        guard linksEnabled else { return true }

        // Extract the URL from the link value. `link` can be URL, NSURL, or String.
        let url: URL? = {
            switch link {
            case let url as URL: return url
            case let nsurl as NSURL: return nsurl as URL
            case let str as String: return URL(string: str)
            default: return nil
            }
        }()

        guard let url else {
            return false
        }

        guard let scheme = url.scheme?.lowercased() else {
            // No scheme — treat as unknown; let the system try.
            return false
        }

        switch scheme {
        case "file":
            // Open as a new editor tab so the preview stays synced.
            Task { [weak self] in
                await self?.router?.open(url)
            }
            return true

        case "http", "https", "mailto":
            // Open in the system browser or mail client.
            NSWorkspace.shared.open(url)
            return true

        case "javascript", "data", "blob":
            // Unsafe schemes — block and log.
            #if DEBUG
                print("[MarkdownPreview] Blocked navigation to \(url.absoluteString)")
            #endif
            return true

        default:
            // Unknown scheme — block for safety.
            #if DEBUG
                print(
                    "[MarkdownPreview] Blocked unknown scheme: \(scheme) in \(url.absoluteString)")
            #endif
            return true
        }
    }
}
