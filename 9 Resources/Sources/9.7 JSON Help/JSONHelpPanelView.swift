import AppKit
import FoundationModule
import SwiftUI

/// The top-level view for the JSON Help sub-module (9.7).
///
/// Wraps `SputnikHelpPanel<JSONHelpContent, ...>` and provides:
/// - Markdown body rendering
/// - Optional read-only JSON code example when a topic includes `exampleJSON`
///
/// Register this view in `ContentView` under `PanelID.jsonHelp`.
public struct JSONHelpPanelView: View {

    @State private var topics: [JSONHelpContent] = []
    @State private var categories: [String] = []
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        if topics.isEmpty {
            Color.clear
                .task {
                    let state = appState
                    JSONHelpCoordinator.shared.onNavigate = { [weak state] request in
                        state?.requestedHelpTarget = request
                    }
                    await loadTopics()
                }
        } else {
            SputnikHelpPanel(
                allTopics: topics,
                categories: categories,
                persistenceKey: "jsonHelp",
                helpKind: .json
            ) { topic in
                jsonTopicContent(topic)
            }
        }
    }

    // MARK: - Topic Content

    @ViewBuilder
    private func jsonTopicContent(_ topic: JSONHelpContent) -> some View {
        VStack(alignment: .leading, spacing: SputnikSpacing.md) {
            // Markdown body
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
                Text(topic.body)
                    .font(.system(size: SputnikFont.body))
                    .foregroundStyle(SputnikColor.primaryText)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }

            // JSON example code block
            if let example = topic.exampleJSON, !example.isEmpty {
                Divider()
                    .padding(.vertical, SputnikSpacing.xs)

                Text("Example")
                    .font(.system(size: SputnikFont.caption, weight: .semibold))
                    .foregroundStyle(SputnikColor.secondaryText)

                ScrollView(.horizontal) {
                    Text(example)
                        .font(.system(size: SputnikFont.caption, design: .monospaced))
                        .foregroundStyle(SputnikColor.primaryText)
                        .textSelection(.enabled)
                        .padding(SputnikSpacing.sm)
                }
                .background(SputnikColor.editorBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(SputnikColor.separator, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Loading

    private func loadTopics() async {
        let index = JSONHelpIndex.shared
        topics = await index.allTopics()
        categories = await index.categories()
    }
}
