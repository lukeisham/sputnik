import Foundation
import Observation

/// The view model for the Markdown Preview panel.
///
/// Owns the rendered output, observes the active Markdown document, and orchestrates
/// the parse pipeline. All published state is `@MainActor`-isolated; the heavy
/// `AttributedString(markdown:)` call runs on a background `Task(priority: .utility)`
/// and the result is published back on the main actor (MR-3, SW-1, SR-4).
///
/// A stale-render guard (generation counter) ensures that if a newer `render` call
/// arrives before the previous one completes, the older result is discarded.
@Observable
@MainActor
public final class MarkdownPreviewViewModel {

    // MARK: - Owned state

    /// The latest successfully rendered Markdown output. Empty by default.
    public var renderedString: AttributedString = AttributedString()

    /// Preserved vertical scroll position across re-renders.
    public var scrollOffset: CGFloat = 0

    /// User-adjustable zoom factor. Range 0.5 … 2.0; default 1.0.
    public var fontScale: CGFloat = 1.0 {
        didSet {
            fontScale = min(2.0, max(0.5, fontScale))
        }
    }

    /// `true` while a background parse is in flight.
    public var isRendering: Bool = false

    /// Non-nil when `AttributedString(markdown:)` threw. Surfaced as a subtle banner.
    public var renderError: String? = nil

    // MARK: - Stale-render guard

    /// Monotonically increasing counter. Each `render` call increments it; the
    /// background task captures the current value and discards its result if the
    /// counter has advanced further by the time it completes.
    private var renderGeneration: UInt64 = 0

    // MARK: - AppState observation

    /// Weak reference to the shared `AppState`, set by the panel on appear.
    /// Held weakly because `AppState` is owned by the app root (SW-2).
    private weak var appState: AppState?

    // MARK: - Public API

    /// Creates a new, empty view model.
    public init() {}

    /// Wires the view model to the shared `AppState`. Called once from
    /// `MarkdownPreviewPanel` when the panel first appears.
    ///
    /// - Parameter appState: The app's shared state. Held weakly.
    public func configure(appState: AppState) {
        self.appState = appState
    }

    /// Renders raw Markdown text into a styled `AttributedString`.
    ///
    /// Runs `AttributedString(markdown:)` on a background `Task(priority: .utility)`.
    /// On success, `renderedString` is published on `@MainActor`. On failure,
    /// `renderError` is set and the raw text is rendered as a plain-text fallback.
    ///
    /// If a newer `render` call arrives before this one completes, the result
    /// is discarded — only the most recent text is ever shown.
    ///
    /// - Parameter markdown: The raw Markdown source text.
    public func render(markdown: String) {
        renderGeneration &+= 1
        let generation = renderGeneration

        isRendering = true
        renderError = nil

        Task.detached(priority: .utility) { [weak self, generation] in
            let result: AttributedString
            do {
                result = try AttributedString(
                    markdown: markdown,
                    options: AttributedString.MarkdownParsingOptions(
                        allowsExtendedAttributes: true,
                        interpretedSyntax: .inlineOnlyPreservingWhitespace
                    )
                )
                await self?.applyRenderedResult(result, generation: generation, markdown: markdown)
            } catch {
                let plain = AttributedString(markdown)
                await self?.applyRenderError(
                    error, rawText: markdown, fallback: plain, generation: generation)
            }
        }
    }

    /// Renders Markdown text at the given font scale.
    ///
    /// The scale is **not** baked into the parsed `AttributedString` — it is applied
    /// downstream in `MarkdownRenderView` via `NSTextView.font` (which scales the base
    /// font for every run uniformly). This method therefore shares the parse path with
    /// `render(markdown:)`; the `fontScale` parameter is retained for call-site clarity
    /// and so the panel can keep `viewModel.fontScale` in sync before re-rendering.
    ///
    /// - Parameters:
    ///   - markdown:   The raw Markdown source text.
    ///   - fontScale:  The zoom factor; applied by the render view, not here.
    public func render(markdown: String, fontScale: CGFloat) {
        render(markdown: markdown)
    }

    // MARK: - Private helpers

    /// Applies a successfully rendered result to `@MainActor` state, guarding against
    /// stale renders from superseded generations.
    @MainActor
    private func applyRenderedResult(
        _ string: AttributedString,
        generation: UInt64,
        markdown: String
    ) {
        guard generation == renderGeneration else { return }
        isRendering = false
        renderError = nil
        renderedString = string
    }

    /// Captures a render error and falls back to plain-text display.
    @MainActor
    private func applyRenderError(
        _ error: any Error,
        rawText: String,
        fallback: AttributedString,
        generation: UInt64
    ) {
        guard generation == renderGeneration else { return }
        isRendering = false
        renderError = error.localizedDescription
        renderedString = fallback
    }
}
