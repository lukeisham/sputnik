import SwiftUI

// MARK: - Markdown Help Panel View

/// The top-level view for the Markdown Help sub-module (9.3).
///
/// Wraps `SputnikHelpPanel<MarkdownHelpContent, ...>` and provides:
/// - Markdown body rendering (inline-only attributed Markdown; delegates to Module 4's
///   full renderer when available)
/// - A "Render" toggle for `exampleCode` snippets — shows raw source and rendered
///   Markdown side by side
/// - Graceful degradation: falls back to raw Markdown text if the app's Markdown
///   pipeline is unavailable
///
/// Register this view in `ContentView` under `PanelID.markdownHelp`.
@MainActor
public struct MarkdownHelpPanelView: View {

    @State private var topics: [MarkdownHelpContent] = []
    @State private var categories: [String] = []
    @State private var hasLoaded: Bool = false

    public init() {}

    public var body: some View {
        if topics.isEmpty && !hasLoaded {
            Color.clear
                .task {
                    hasLoaded = true
                    let index = MarkdownHelpIndex.shared
                    topics = await index.allTopics()
                    categories = await index.categories()
                }
        } else {
            SputnikHelpPanel(
                allTopics: topics,
                categories: categories,
                persistenceKey: "markdownHelp"
            ) { topic in
                markdownTopicContent(topic)
            }
        }
    }

    // MARK: - Topic Content

    @ViewBuilder
    private func markdownTopicContent(_ topic: MarkdownHelpContent) -> some View {
        VStack(alignment: .leading, spacing: SputnikSpacing.md) {
            // Render the body text as Markdown (inline-only to keep it simple;
            // a full CommonMark pipeline from Module 4 can be swapped in here.)
            markdownBodyView(topic)

            // Example code with "Render" toggle
            if let example = topic.exampleCode, !example.isEmpty {
                Divider()
                MarkdownExampleView(rawMarkdown: example)
            }
        }
    }

    // MARK: - Body Rendering

    /// Renders the Markdown body using `AttributedString`'s built-in Markdown
    /// support (inline-only). When Module 4's full renderer is ready, the
    /// `Topic` content builder can be swapped to a `NSViewRepresentable` that
    /// feeds the body to the Markdown preview pipeline.
    @ViewBuilder
    private func markdownBodyView(_ topic: MarkdownHelpContent) -> some View {
        if let attributed = try? AttributedString(
            markdown: topic.body,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.system(size: SputnikFont.body))
                .foregroundStyle(SputnikColor.primaryText)
                .lineSpacing(4)
                .textSelection(.enabled)
        } else {
            // Graceful degradation: plain text
            Text(topic.body)
                .font(.system(size: SputnikFont.body))
                .foregroundStyle(SputnikColor.primaryText)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Markdown Example View

/// Displays an `exampleCode` Markdown snippet with a "Render" toggle: one
/// pane shows the raw Markdown source, the other shows the rendered output.
///
/// Each topic tab gets its own toggle state so switching tabs remembers which
/// view was active.
@MainActor
private struct MarkdownExampleView: View {

    let rawMarkdown: String

    @State private var showRendered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: SputnikSpacing.xs) {
            HStack {
                Text("Example")
                    .font(.system(size: SputnikFont.caption, weight: .semibold))
                    .foregroundStyle(SputnikColor.secondaryText)
                Spacer()
                Picker("View", selection: $showRendered) {
                    Text("Source").tag(false)
                    Text("Rendered").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if showRendered {
                // Rendered Markdown output
                if let attributed = try? AttributedString(
                    markdown: rawMarkdown,
                    options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ) {
                    Text(attributed)
                        .font(.system(size: SputnikFont.body))
                        .foregroundStyle(SputnikColor.primaryText)
                        .padding(SputnikSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SputnikColor.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Text(rawMarkdown)
                        .font(.system(size: SputnikFont.body))
                        .foregroundStyle(SputnikColor.primaryText)
                        .padding(SputnikSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SputnikColor.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } else {
                // Raw Markdown source
                Text(rawMarkdown)
                    .font(.system(size: SputnikFont.caption, design: .monospaced))
                    .foregroundStyle(SputnikColor.primaryText)
                    .padding(SputnikSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SputnikColor.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
