import SwiftUI

/// A SwiftUI view wrapping `SputnikHelpPanel` for Grammar Help topics.
///
/// Loads topics from `GrammarHelpIndex.shared` on appear, then delegates all tab,
/// search, sidebar, and persistence behaviour to the shared panel. Topic bodies are
/// rendered as Markdown with special ✅/❌ styling: lines starting with `✅` render
/// in `SputnikColor.accent`, and lines starting with `❌` render in a red-tinted
/// colour with a strikethrough.
public struct GrammarHelpPanelView: View {

    @State private var topics: [GrammarHelpContent] = []
    @State private var categories: [String] = []

    public init() {}

    public var body: some View {
        SputnikHelpPanel(
            allTopics: topics,
            categories: categories,
            persistenceKey: "grammarHelp",
            helpKind: .grammar
        ) { topic in
            GrammarHelpTopicContentView(topic: topic)
        }
        .task {
            let index = GrammarHelpIndex.shared
            topics = await index.allTopics()
            categories = await index.categories()
        }
    }
}

// MARK: - Topic Content View

/// Renders a single Grammar Help topic body line-by-line so that `✅` and `❌`
/// markers receive distinct visual treatment.
private struct GrammarHelpTopicContentView: View {
    let topic: GrammarHelpContent

    var body: some View {
        VStack(alignment: .leading, spacing: SputnikSpacing.xs) {
            ForEach(lines, id: \.self) { line in
                grammarHelpLine(line)
            }
        }
    }

    /// The topic body split into individual lines, preserving empty lines.
    private var lines: [String] {
        topic.body.components(separatedBy: "\n")
    }

    @ViewBuilder
    private func grammarHelpLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("✅") {
            Text(line)
                .font(.system(size: SputnikFont.body, design: .monospaced))
                .foregroundStyle(SputnikColor.accent)
        } else if trimmed.hasPrefix("❌") {
            Text(line)
                .font(.system(size: SputnikFont.body, design: .monospaced))
                .foregroundStyle(grammarIncorrectColor)
                .strikethrough(true, color: grammarIncorrectColor)
        } else {
            Text(line)
                .font(.system(size: SputnikFont.body))
                .foregroundStyle(SputnikColor.primaryText)
        }
    }

    /// A red-tinted colour for incorrect usage examples.
    private var grammarIncorrectColor: Color {
        Color(red: 0.85, green: 0.22, blue: 0.22)
    }
}
