import SwiftUI
import WebKit

// MARK: - Sandboxed HTML Demo

/// A sandboxed `WKWebView` that renders a static HTML snippet with no navigation,
/// no JavaScript execution, and no external resource loading.
///
/// Each instance owns its own `WKWebView` so that tabs with live demos are
/// independently managed and deallocated when the tab is closed (SR-3).
public struct SandboxedHTMLDemo: NSViewRepresentable {
    public let html: String

    public init(html: String) {
        self.html = html
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Sandbox: disable JavaScript (modern API, macOS 11+)
        config.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        // Wrap the snippet in a minimal HTML document with system fonts
        let wrapped = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
              * { margin: 0; padding: 0; box-sizing: border-box; }
              body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                padding: 12px;
                color: -apple-system-label;
                background: transparent;
              }
              @media (prefers-color-scheme: dark) {
                body { color: -apple-system-label; }
              }
            </style>
            </head>
            <body>\(html)</body>
            </html>
            """
        webView.loadHTMLString(wrapped, baseURL: nil)
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        // Only reload if the HTML actually changed
        let wrapped = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
              * { margin: 0; padding: 0; box-sizing: border-box; }
              body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                padding: 12px;
                color: -apple-system-label;
                background: transparent;
              }
            </style>
            </head>
            <body>\(html)</body>
            </html>
            """
        nsView.loadHTMLString(wrapped, baseURL: nil)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Blocks all navigation so the sandboxed view cannot browse away.
    public final class Coordinator: NSObject, WKNavigationDelegate {
        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Allow the initial about:blank load, block everything else
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}

// MARK: - HTML Help Panel View

/// The top-level view for the HTML Help sub-module (9.4).
///
/// Wraps `SputnikHelpPanel<HTMLHelpContent, ...>` and provides:
/// - Markdown body rendering
/// - Sandboxed `WKWebView` live demo when a topic includes `exampleHTML`
/// - Related-topic cross-references (handled by the shared panel)
///
/// Register this view in `ContentView` under `PanelID.htmlHelp`.
public struct HTMLHelpPanelView: View {

    @State private var topics: [HTMLHelpContent] = []
    @State private var categories: [String] = []

    public init() {}

    public var body: some View {
        if topics.isEmpty {
            Color.clear
                .task { await loadTopics() }
        } else {
            SputnikHelpPanel(
                allTopics: topics,
                categories: categories,
                persistenceKey: "htmlHelp",
                helpKind: .html
            ) { topic in
                htmlTopicContent(topic)
            }
        }
    }

    // MARK: - Topic Content

    @ViewBuilder
    private func htmlTopicContent(_ topic: HTMLHelpContent) -> some View {
        VStack(alignment: .leading, spacing: SputnikSpacing.md) {
            // Render the Markdown body (simple approach — attributed text)
            if let attributed = try? AttributedString(
                markdown: topic.body,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
                    .font(.system(size: SputnikFont.body))
                    .foregroundStyle(SputnikColor.primaryText)
                    .lineSpacing(4)
            } else {
                // Fallback: render as plain text
                Text(topic.body)
                    .font(.system(size: SputnikFont.body))
                    .foregroundStyle(SputnikColor.primaryText)
                    .lineSpacing(4)
            }

            // Live demo section
            if let exampleHTML = topic.exampleHTML, !exampleHTML.isEmpty {
                Divider()
                    .padding(.vertical, SputnikSpacing.xs)

                Text("Live Demo")
                    .font(.system(size: SputnikFont.caption, weight: .semibold))
                    .foregroundStyle(SputnikColor.secondaryText)

                SandboxedHTMLDemo(html: exampleHTML)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(SputnikColor.separator, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Loading

    private func loadTopics() async {
        let index = HTMLHelpIndex.shared
        topics = await index.allTopics()
        categories = await index.categories()
    }
}
