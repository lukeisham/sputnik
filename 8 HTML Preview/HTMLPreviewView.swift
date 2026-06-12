import AppKit
import FoundationModule
import Observation
import ResourcesModule
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

    /// The settings store, read for per-panel font and background (F-4).
    private let settings: SettingsStore

    /// Binding to a print-action closure. The view sets this in `updateNSView` so the
    /// parent panel can trigger a print of the `WKWebView` content.
    @Binding private var printAction: (() -> Void)?

    /// Binding to a save-as-PDF closure. The view sets this in `updateNSView` so the
    /// parent panel can trigger a PDF export of the `WKWebView` content.
    @Binding private var saveAsPDFAction: (() -> Void)?

    /// Binding to a save-as-HTML closure. The view sets this in `updateNSView` so the
    /// parent panel can export the active document's raw HTML source to a `.html` file.
    @Binding private var saveAsHTMLAction: (() -> Void)?

    /// When `true`, the preview follows the editor's fractional scroll position (ISS-063).
    /// `false` for large files (>80k chars) or when the user has disabled sync (Step 10).
    private let syncScrollEnabled: Bool

    // MARK: - Init

    /// Creates the HTML preview view.
    /// - Parameters:
    ///   - router:                  The app's `InterPanelRouter` instance.
    ///   - isLinkNavigationEnabled: Whether link clicks open files/URLs. Default `true`.
    ///   - onLoadError:             Optional callback when navigation fails.
    ///   - helpContextResolver:     Resolver for "More Context" right-click help. Defaults to
    ///                              `SputnikHelpContextResolver.shared`.
    ///   - settings:                The app settings store (for per-panel font/background).
    ///   - printAction:             Binding set by the view with the print closure.
    ///   - saveAsPDFAction:          Binding set by the view with the save-as-PDF closure.
    ///   - saveAsHTMLAction:         Binding set by the view with the save-as-HTML closure.
    @MainActor
    public init(
        router: (any InterPanelRouter)? = nil,
        isLinkNavigationEnabled: Bool = true,
        syncScrollEnabled: Bool = false,
        onLoadError: ((String) -> Void)? = nil,
        helpContextResolver: HelpContextResolving? = nil,
        settings: SettingsStore,
        printAction: Binding<(() -> Void)?> = .constant(nil),
        saveAsPDFAction: Binding<(() -> Void)?> = .constant(nil),
        saveAsHTMLAction: Binding<(() -> Void)?> = .constant(nil)
    ) {
        self.router = router
        self.isLinkNavigationEnabled = isLinkNavigationEnabled
        self.syncScrollEnabled = syncScrollEnabled
        self.onLoadError = onLoadError
        self.helpContextResolver = helpContextResolver ?? SputnikHelpContextResolver.shared
        self.settings = settings
        _printAction = printAction
        _saveAsPDFAction = saveAsPDFAction
        _saveAsHTMLAction = saveAsHTMLAction
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

        // Register the sputnik-img scheme handler for downsampled image streaming (ISS-047).
        let imageHandler = SputnikImageSchemeHandler()
        imageHandler.coordinator = context.coordinator
        configuration.setURLSchemeHandler(imageHandler, forURLScheme: "sputnik-img")

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

        guard let session, session.fileType == FileType.html else {
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
        context.coordinator.webView = webView

        // Wire the print action so the panel's overflow menu can trigger printing.
        context.coordinator.printAction = { [weak webView] in
            guard let webView, let window = webView.window else { return }
            let printOp = NSPrintOperation(view: webView, printInfo: .shared)
            printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
        printAction = context.coordinator.printAction

        // Wire the save-as-PDF action.
        context.coordinator.saveAsPDFAction = { [weak webView] in
            guard let webView, let window = webView.window else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            let suggestedName = context.coordinator.currentBaseURL?.lastPathComponent ?? "document"
            panel.nameFieldStringValue = (suggestedName as NSString).deletingPathExtension + ".pdf"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                let config = WKPDFConfiguration()
                config.rect = .zero  // full document
                webView.createPDF(configuration: config) { result in
                    switch result {
                    case .success(let data):
                        do {
                            try data.write(to: url)
                        } catch {
                            let alert = NSAlert()
                            alert.messageText = "Save as PDF Failed"
                            alert.informativeText = error.localizedDescription
                            alert.alertStyle = .warning
                            alert.runModal()
                        }
                    case .failure(let error):
                        let alert = NSAlert()
                        alert.messageText = "PDF Generation Failed"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        }
        saveAsPDFAction = context.coordinator.saveAsPDFAction

        // Wire the save-as-HTML action.
        context.coordinator.saveAsHTMLAction = { [weak webView] in
            guard let webView, let window = webView.window else { return }
            let sourceText = session.text  // raw source, no F-4 CSS injected
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.html]
            let baseName =
                (context.coordinator.currentBaseURL?.deletingPathExtension().lastPathComponent)
                ?? "document"
            panel.nameFieldStringValue = baseName + ".html"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                Task(priority: .userInitiated) {
                    do {
                        try sourceText.write(to: url, atomically: true, encoding: .utf8)
                    } catch {
                        await MainActor.run {
                            let alert = NSAlert()
                            alert.messageText = "Save as HTML Failed"
                            alert.informativeText = error.localizedDescription
                            alert.alertStyle = .warning
                            alert.runModal()
                        }
                    }
                }
            }
        }
        saveAsHTMLAction = context.coordinator.saveAsHTMLAction

        // Inject per-panel font and background CSS (F-4), then load (throttled — SR-4).
        let styled = htmlByInjectingOverrides(session.text, settings: settings)
        context.coordinator.throttledLoad(html: styled, baseURL: baseURL)

        // Apply editor→preview scroll sync (ISS-063, Steps 3 & 5).
        // Accessing editorScrollFraction when syncScrollEnabled is true causes SwiftUI to
        // observe it via @Observable, so updateNSView is re-invoked on each scroll event.
        if syncScrollEnabled, let fraction = appState.editorScrollFraction {
            context.coordinator.syncScrollToFraction(fraction)
        }
    }

    // MARK: - F-4 CSS injection and image rewriting

    /// Wraps user HTML content with CSS overrides for the per-panel font and
    /// background colour. Also rewrites local `<img src>` paths to use the
    /// `sputnik-img://` scheme handler (ISS-047). If the user HTML already has a `<head>`,
    /// the style block is injected before `</head>`; otherwise the content is wrapped in
    /// a minimal HTML document.
    /// - Parameters:
    ///   - html:     The raw HTML from the editor session.
    ///   - settings: The settings store (read for `resolvedHtmlPreviewFont` and
    ///               `htmlPreviewBackground`).
    /// - Returns: Modified HTML string with injected style overrides and rewritten img src.
    private func htmlByInjectingOverrides(_ html: String, settings: SettingsStore) -> String {
        let bg = NSColor(settings.htmlPreviewBackground)
        let font = settings.resolvedHtmlPreviewFont

        guard let rgb = bg.usingColorSpace(.deviceRGB) else {
            return html
        }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        let hex = String(format: "#%02X%02X%02X", r, g, b)

        let css = """
            <style>
              body {
                background-color: \(hex) !important;
              }
              body, p, div, h1, h2, h3, h4, h5, h6, li, td, th, blockquote, pre, code {
                font-family: '\(font.postScriptName)', -apple-system, sans-serif !important;
                font-size: \(String(format: "%.1f", font.pointSize))pt !important;
              }
            </style>
            """

        // Rewrite local <img src> paths to use the sputnik-img scheme
        let rewritten = rewriteLocalImageSources(html)

        if let headEnd = rewritten.range(of: "</head>", options: .caseInsensitive) {
            return rewritten.replacingCharacters(in: headEnd, with: css + "</head>")
        }

        if rewritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Empty content — load placeholder
            return placeholderHTML
        }

        // No head tag — wrap in a minimal document.
        return """
            <!DOCTYPE html>
            <html>
            <head><meta charset="utf-8">\(css)</head>
            <body>\(rewritten)</body>
            </html>
            """
    }

    /// Rewrites local `<img src="…">` paths to use the `sputnik-img://` scheme.
    /// Leaves `http(s)`, protocol-relative, and existing `data:` URIs untouched.
    private func rewriteLocalImageSources(_ html: String) -> String {
        var result = html
        // Match <img ... src="..." ... > with capturing group for the src value
        let pattern = #"<img\s+([^>]*?\s+)?src="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return html
        }

        let nsString = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))

        // Process matches in reverse order to maintain string indices
        for match in matches.reversed() {
            if match.numberOfRanges < 3 { continue }
            let srcRange = match.range(at: 2)
            let srcValue = nsString.substring(with: srcRange)

            // Skip remote URLs and data URIs
            if srcValue.hasPrefix("http://") || srcValue.hasPrefix("https://")
                || srcValue.hasPrefix("//") || srcValue.hasPrefix("data:")
            {
                continue
            }

            // Rewrite local path to sputnik-img scheme
            if let encoded = srcValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            {
                let newSrc = "sputnik-img://host/\(encoded)"
                let fullRange = NSRange(location: srcRange.location, length: srcRange.length)
                result = nsString.replacingCharacters(in: fullRange, with: newSrc) as String
            }
        }

        return result
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
