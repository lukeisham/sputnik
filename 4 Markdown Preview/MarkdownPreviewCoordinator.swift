import AppKit
import FoundationModule
import ResourcesModule
import SwiftUI

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

    /// Closure invoked when the user selects "More Context" to request a help panel.
    /// Wired by `MarkdownPreviewPanel`.
    public var onRequestHelp: ((HelpRequest?) -> Void)?

    /// The shared help-context resolver, used to build context-menu items.
    /// Falls back to `SputnikHelpContextResolver.shared` when `nil`.
    public var helpContextResolver: HelpContextResolving?

    /// When `false`, link-click handling is disabled entirely and all clicks
    /// become selection-only gestures. Toggled from the panel toolbar.
    public var linksEnabled: Bool = true

    // MARK: - Scroll tracking (wired by MarkdownRenderView)

    /// Retained token from `NotificationCenter.addObserver` for scroll-position tracking.
    /// Managed by `MarkdownRenderView.updateNSView`; removed and replaced whenever the
    /// hosting scroll view changes (e.g. when `fitWidth` toggles the view tree).
    var scrollObserverToken: Any?

    /// The clip view currently being observed. Used to detect when the hosting scroll view
    /// changes so the observer is re-registered against the new clip view.
    weak var observedClipView: NSClipView?

    /// Binding into `MarkdownPreviewPanel.scrollOffsets` for the active document.
    /// Updated on every `updateNSView` call so the observer always writes to the right slot.
    var scrollOffsetBinding: Binding<CGFloat>?

    // MARK: - Editor→preview scroll sync (ISS-063, Step 5)

    /// Last fractional position applied by scroll sync. Guards against feedback loops
    /// and unnecessary layout: the preview only scrolls when the fraction shifts >0.005.
    var lastSyncScrollFraction: Double = -1

    // MARK: - Bidirectional navigation (ISS-065, Step 9)

    /// When `true`, ⌘-click on rendered text reveals the corresponding source line in the editor.
    /// Disabled automatically when `viewModel.isLargeFile` (Step 10).
    var bidirectionalEnabled: Bool = false

    /// Weak reference to the view model for source-map lookups. Held weakly to avoid
    /// a retain cycle (coordinator → viewModel → coordinator via delegate). (SW-2)
    weak var viewModel: MarkdownPreviewViewModel?

    // MARK: - Save-as-Markdown export context

    /// The raw Markdown source text of the active document. Set by `MarkdownRenderView.updateNSView`
    /// before the save-as-Markdown closure is wired, then read when the user triggers the export.
    var currentSourceText: String = ""

    /// The filename (without parent directory) of the active document. Used to derive the
    /// default `.md` export filename.
    var currentDocumentName: String = ""

    // MARK: - Export / print actions (ISS-095)

    /// Print the rendered Markdown. Wired once in `MarkdownRenderView.makeNSView` and read
    /// by `MarkdownPreviewPanel` — moved off `updateNSView` to avoid mutating SwiftUI state
    /// during a view update (ISS-095). `nil` until the render view has been created.
    var printAction: (() -> Void)?

    /// Export the rendered Markdown as a PDF via an `NSSavePanel`. See `printAction`.
    var saveAsPDFAction: (() -> Void)?

    /// Export the raw Markdown source as a `.md` file via an `NSSavePanel`. See `printAction`.
    var saveAsMarkdownAction: (() -> Void)?

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

    // MARK: - Bidirectional click handler (ISS-065, Step 9)

    /// Fired by an `NSClickGestureRecognizer` added to the preview text view.
    /// When ⌘ is held and `bidirectionalEnabled` is true, maps the clicked character
    /// position back to a source line via `viewModel.sourceMap` and reveals it in the editor.
    /// Yields silently when the click lands on a link — the delegate handles those instead.
    @objc func handleCommandClick(_ recognizer: NSClickGestureRecognizer) {
        guard bidirectionalEnabled,
            NSApp.currentEvent?.modifierFlags.contains(.command) == true,
            let textView = recognizer.view as? NSTextView,
            let storage = textView.textStorage
        else { return }

        let point = recognizer.location(in: textView)
        let charIndex = textView.characterIndex(for: point)
        guard charIndex != NSNotFound, charIndex < storage.length else { return }

        // Let the NSTextViewDelegate handle ⌘-clicks on actual links.
        if storage.attribute(.link, at: charIndex, effectiveRange: nil) != nil { return }

        guard let map = viewModel?.sourceMap,
            let block = map.first(where: { $0.contains(renderedOffset: charIndex) })
        else { return }

        Task { [weak self] in
            self?.router?.revealSourceLine(block.sourceStartLine)
        }
    }

    // MARK: - Context Menu

    /// Intercepts the right-click context menu and injects "More Context" items for
    /// Grammar Help and Markdown Help when text is selected.
    ///
    /// - Parameters:
    ///   - textView:      The text view that received the right-click.
    ///   - menu:          The default context menu.
    ///   - charIndex:     The character index of the click.
    ///   - selectedRange: The current selection range.
    /// - Returns: The modified menu, or `nil` to use the default.
    public func textView(
        _ textView: NSTextView,
        menu: NSMenu,
        at charIndex: Int,
        for selectedRange: NSRange
    ) -> NSMenu? {
        // Extract the selected text from the text view's storage.
        // `attributedSubstring(from:)` is non-optional but traps on an out-of-range
        // range, so bound the selection against the storage length first (SR-2).
        guard let storage = textView.textStorage,
            NSMaxRange(selectedRange) <= storage.length
        else {
            return menu
        }
        let selected = storage.attributedSubstring(from: selectedRange).string
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return menu
        }

        let fullText = textView.string
        let resolver = helpContextResolver ?? SputnikHelpContextResolver.shared

        let moreItems = MoreContextMenu.items(
            forSelectedText: selected,
            kinds: [.grammar, .markdown],
            fullText: fullText,
            cursorOffset: selectedRange.location,
            resolver: resolver,
            onRequest: { [weak self] request in
                self?.onRequestHelp?(request)
            }
        )

        guard !moreItems.isEmpty else { return menu }

        let updatedMenu = menu.copy() as? NSMenu ?? menu
        updatedMenu.insertItem(.separator(), at: 0)
        for item in moreItems.reversed() {
            updatedMenu.insertItem(item, at: 0)
        }
        return updatedMenu
    }
}
