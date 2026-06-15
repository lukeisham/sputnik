import AppKit
import SwiftUI
import WebKit

/// Bridges a `WKWebView` to a `MinimapView` using injected JavaScript.
///
/// Reads top-level block elements' heights and tags from the DOM to build a
/// `MinimapModel`. Viewport tracking uses `scrollY` / `scrollHeight`. On interaction,
/// calls `window.scrollTo`. Mirrors `HTMLPreviewCoordinator.syncScrollToFraction`.
///
/// **Fidelity note:** The HTML minimap is DOM-approximate (block heights), not
/// pixel-exact — acceptable for navigation.
///
/// Holds a **weak** reference to the target `WKWebView` (SW-2, ISS-093).
public struct MinimapWebBinder: NSViewRepresentable {

    /// Weak reference to the target web view.
    let target: WKWebView?

    /// The settings store, read for `minimapOpacity`.
    let settings: SettingsStore

    /// The app state, read for `minimapVisible`.
    let appState: AppState

    public init(target: WKWebView?, settings: SettingsStore, appState: AppState) {
        self.target = target
        self.settings = settings
        self.appState = appState
    }

    // MARK: - NSViewRepresentable

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> MinimapView {
        let view = MinimapView()
        view.onScrollToFraction = { [weak target] fraction in
            guard let target else { return }
            let js = """
                (function(){
                    var h = document.documentElement.scrollHeight
                          - document.documentElement.clientHeight;
                    if (h > 0) window.scrollTo(0, Math.round(h * \(fraction)));
                })();
                """
            target.evaluateJavaScript(js, completionHandler: nil)
        }
        view.minimapOpacity = settings.minimapOpacity

        // Start polling the DOM.
        context.coordinator.startPolling(
            target: target,
            minimapView: view
        )

        return view
    }

    public func updateNSView(_ nsView: MinimapView, context: Context) {
        nsView.minimapOpacity = settings.minimapOpacity

        if context.coordinator.observedWebView !== target {
            context.coordinator.stopPolling()
            context.coordinator.startPolling(
                target: target,
                minimapView: nsView
            )
        }
    }

    public static func dismantleNSView(
        _ nsView: MinimapView, coordinator: Coordinator
    ) {
        coordinator.stopPolling()
        nsView.onScrollToFraction = nil
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator {
        private(set) weak var observedWebView: WKWebView?
        private weak var minimapView: MinimapView?
        private var pollTimer: Timer?
        private var lastModel: MinimapModel = .empty
        private var contentHash: Int = 0

        func startPolling(target: WKWebView?, minimapView: MinimapView) {
            self.observedWebView = target
            self.minimapView = minimapView
            self.contentHash = 0

            // Poll every 0.5 s for model + viewport updates.
            pollTimer = Timer.scheduledTimer(
                withTimeInterval: 0.5, repeats: true
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.pollDOM()
                }
            }
        }

        func stopPolling() {
            pollTimer?.invalidate()
            pollTimer = nil
            observedWebView = nil
            minimapView = nil
        }

        // MARK: - DOM polling

        private func pollDOM() {
            guard let webView = observedWebView else { return }

            // Read block heights + scroll position from DOM.
            let js = """
                (function(){
                    var blocks = document.querySelectorAll(
                        'p, h1, h2, h3, h4, h5, h6, pre, blockquote, ul, ol, li, div, section, article, header, footer, hr, br'
                    );
                    var lines = [];
                    var maxH = 0;
                    blocks.forEach(function(b){
                        var rect = b.getBoundingClientRect();
                        var h = rect.height;
                        if (h > 0) {
                            var tag = b.tagName.toLowerCase();
                            lines.push({h: h, t: tag});
                            maxH = Math.max(maxH, h);
                        }
                    });
                    return JSON.stringify({
                        blocks: lines,
                        maxHeight: maxH,
                        scrollY: window.scrollY,
                        scrollHeight: document.documentElement.scrollHeight,
                        clientHeight: document.documentElement.clientHeight
                    });
                })();
                """

            webView.evaluateJavaScript(js) { [weak self] result, error in
                guard let self,
                    let json = result as? String,
                    let data = json.data(using: .utf8),
                    let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let blocks = dict["blocks"] as? [[String: Any]]
                else { return }

                // Build MinimapModel from DOM blocks.
                let lines = blocks.compactMap { block -> MinimapLine? in
                    guard let h = block["h"] as? Double,
                        let tag = block["t"] as? String,
                        let maxH = dict["maxHeight"] as? Double
                    else { return nil }
                    let fraction = maxH > 0 ? min(1.0, h / maxH) : 0
                    let kind = Self.classifyDOMTag(tag)
                    return MinimapLine(lengthFraction: fraction, kind: kind)
                }

                let model = MinimapModel(lines: lines)

                // Suppress redundant updates (same content hash).
                var hasher = Hasher()
                hasher.combine(lines.count)
                for line in lines {
                    hasher.combine(line.lengthFraction)
                    hasher.combine(line.kind)
                }
                let newHash = hasher.finalize()
                if newHash != self.contentHash {
                    self.contentHash = newHash
                    self.minimapView?.model = model
                }

                // Update viewport fraction.
                if let scrollY = dict["scrollY"] as? Double,
                    let scrollHeight = dict["scrollHeight"] as? Double,
                    let clientHeight = dict["clientHeight"] as? Double
                {
                    let maxScroll = max(0, scrollHeight - clientHeight)
                    let fraction = maxScroll > 0 ? scrollY / maxScroll : 0
                    self.minimapView?.viewportFraction = max(0, min(1.0, fraction))
                }
            }
        }

        // MARK: - DOM tag classification

        private static func classifyDOMTag(_ tag: String) -> LineKind {
            switch tag {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                return .heading
            case "pre", "code":
                return .code
            case "blockquote":
                return .quote
            case "ul", "ol", "li":
                return .list
            case "hr", "br":
                return .blank
            default:
                return .plain
            }
        }
    }
}
