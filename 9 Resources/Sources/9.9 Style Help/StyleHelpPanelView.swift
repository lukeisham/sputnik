import FoundationModule
import SwiftUI

/// A SwiftUI view wrapping `SputnikHelpPanel` for Style Help topics.
///
/// Loads topics from `StyleHelpIndex.shared` on appear, then delegates all tab,
/// search, sidebar, and persistence behaviour to the shared panel. Topic bodies are
/// rendered as Markdown with special ✅/❌ styling: lines starting with `✅` render
/// in `SputnikColor.accent`, and lines starting with `❌` render in a red-tinted
/// colour with a strikethrough.
public struct StyleHelpPanelView: View {

    @State private var topics: [StyleHelpContent] = []
    @State private var categories: [String] = []
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        SputnikHelpPanel(
            allTopics: topics,
            categories: categories,
            persistenceKey: "styleHelp",
            helpKind: .style
        ) { topic in
            StyleHelpTopicContentView(topic: topic)
        }
        .task {
            let state = appState
            StyleHelpCoordinator.shared.onNavigate = { [weak state] request in
                state?.requestedHelpTarget = request
            }
            let index = StyleHelpIndex.shared
            topics = await index.allTopics()
            categories = await index.categories()
        }
    }
}

// MARK: - Topic Content View

/// Renders a single Style Help topic body line-by-line so that `✅` and `❌`
/// markers receive distinct visual treatment.
private struct StyleHelpTopicContentView: View {
    let topic: StyleHelpContent

    var body: some View {
        VStack(alignment: .leading, spacing: SputnikSpacing.xs) {
            ForEach(lines, id: \.self) { line in
                styleHelpLine(line)
            }
        }
    }

    private var lines: [String] {
        topic.body.components(separatedBy: "\n")
    }

    @ViewBuilder
    private func styleHelpLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("✅") {
            Text(line)
                .font(.system(size: SputnikFont.body, design: .monospaced))
                .foregroundStyle(SputnikColor.accent)
                .textSelection(.enabled)
        } else if trimmed.hasPrefix("❌") {
            Text(line)
                .font(.system(size: SputnikFont.body, design: .monospaced))
                .foregroundStyle(styleIncorrectColor)
                .strikethrough(true, color: styleIncorrectColor)
                .textSelection(.enabled)
        } else {
            Text(line)
                .font(.system(size: SputnikFont.body))
                .foregroundStyle(SputnikColor.primaryText)
                .textSelection(.enabled)
        }
    }

    private var styleIncorrectColor: Color {
        Color(red: 0.85, green: 0.22, blue: 0.22)
    }
}
