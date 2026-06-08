import SwiftUI

// MARK: - ASCII Art Help Panel View

/// A SwiftUI view that wraps `SputnikHelpPanel` with ASCII Art Help–specific
/// topic-content rendering.
///
/// Responsibilities:
/// - Loads topics and categories from `ASCIIArtHelpIndex.shared`.
/// - Loads full `.md` body content per topic from the bundle (lazily, on display).
/// - Resolves `@{art:ID}` placeholders by calling `ASCIILibrary.shared.art(id:)`
///   and renders the result in a monospaced code block.
/// - Shows `exampleCode` in a styled code block.
/// - Shows a "Related Art" section listing referenced library pieces.
///
/// All async work stays off the main actor via `Task`; UI updates are dispatched
/// to `@MainActor` state.
@MainActor
public struct ASCIIArtHelpPanelView: View {

    // MARK: - State

    @State private var allTopics: [ASCIIArtHelpContent] = []
    @State private var categories: [String] = []
    @State private var hasLoaded: Bool = false

    // MARK: - Body

    public var body: some View {
        SputnikHelpPanel(
            allTopics: allTopics,
            categories: categories,
            persistenceKey: "asciiArtHelp"
        ) { topic in
            ASCIIArtTopicContentView(topic: topic)
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            let index = ASCIIArtHelpIndex.shared
            allTopics = await index.allTopics()
            categories = await index.categories()
        }
    }

    // MARK: - Init

    public init() {}
}

// MARK: - Topic Content View

/// Renders the full content of a single ASCII Art Help topic.
///
/// - Loads the full `.md` body from the bundle using the topic ID as a file path.
/// - Parses `@{art:ID}` placeholders out of the body and injects ASCII art
///   resolved from `ASCIILibrary.shared`.
/// - Displays `exampleCode` in a styled code block.
/// - Lists referenced art in a "Related Art" section.
@MainActor
private struct ASCIIArtTopicContentView: View {

    // MARK: - Properties

    let topic: ASCIIArtHelpContent

    // MARK: - State

    @State private var resolvedBody: String?
    @State private var resolvedArt: [(id: String, art: String)] = []
    @State private var isLoadingArt: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: SputnikSpacing.md) {

            // MARK: Body with injected art
            if let bodyText = resolvedBody {
                renderedBody(bodyText)
            } else {
                // Show the index summary while the full body loads.
                Text(topic.body)
                    .font(.system(size: SputnikFont.body))
                    .foregroundStyle(SputnikColor.primaryText)
                    .task {
                        resolvedBody = loadMarkdownBody(for: topic.id)
                    }
            }

            // MARK: Example Code
            if let example = topic.exampleCode, !example.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: SputnikSpacing.xs) {
                    Text("Example")
                        .font(.system(size: SputnikFont.caption, weight: .semibold))
                        .foregroundStyle(SputnikColor.secondaryText)

                    Text(example)
                        .font(.system(size: SputnikFont.caption, design: .monospaced))
                        .foregroundStyle(SputnikColor.primaryText)
                        .padding(SputnikSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SputnikColor.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // MARK: Related Art
            if !topic.relatedArtIDs.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: SputnikSpacing.sm) {
                    Text("Related Art")
                        .font(.system(size: SputnikFont.caption, weight: .semibold))
                        .foregroundStyle(SputnikColor.secondaryText)

                    if isLoadingArt {
                        ProgressView()
                            .controlSize(.small)
                    } else if resolvedArt.isEmpty {
                        Text("Loading art pieces...")
                            .font(.system(size: SputnikFont.caption))
                            .foregroundStyle(SputnikColor.tertiaryText)
                            .task {
                                await loadRelatedArt()
                            }
                    } else {
                        ForEach(resolvedArt, id: \.id) { item in
                            VStack(alignment: .leading, spacing: SputnikSpacing.xs) {
                                Text(item.id)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(SputnikColor.tertiaryText)

                                Text(item.art)
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
            }
        }
        .task {
            // Kick off art resolution early — overlaps with body rendering.
            await loadRelatedArt()
        }
    }

    // MARK: - Body Rendering

    /// Renders the full body text, splitting on `@{art:ID}` placeholders and
    /// injecting resolved art inline.
    @ViewBuilder
    private func renderedBody(_ text: String) -> some View {
        let segments = parsePlaceholders(in: text)

        VStack(alignment: .leading, spacing: SputnikSpacing.sm) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let markdown):
                    // Render as plain text with basic Markdown-like formatting.
                    // For a full Markdown pipeline, this would delegate to the app's
                    // Markdown renderer. Here we use simple attributed text.
                    Text(.init(markdown))
                        .font(.system(size: SputnikFont.body))
                        .foregroundStyle(SputnikColor.primaryText)
                        .textSelection(.enabled)

                case .artPlaceholder(let artID):
                    if let art = resolvedArt.first(where: {
                        $0.id.lowercased() == artID.lowercased()
                    }) {
                        VStack(alignment: .leading, spacing: SputnikSpacing.xs) {
                            Text("Art: \(art.id)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(SputnikColor.tertiaryText)

                            Text(art.art)
                                .font(.system(size: SputnikFont.caption, design: .monospaced))
                                .foregroundStyle(SputnikColor.accent)
                                .padding(SputnikSpacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(SputnikColor.secondaryBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    } else {
                        Text("[Art: \(artID) — not found]")
                            .font(.system(size: SputnikFont.caption, design: .monospaced))
                            .foregroundStyle(SputnikColor.tertiaryText)
                            .italic()
                    }
                }
            }
        }
    }

    // MARK: - Art Resolution

    /// Loads all related art pieces from the ASCII Library.
    private func loadRelatedArt() async {
        guard !topic.relatedArtIDs.isEmpty, resolvedArt.isEmpty else { return }
        isLoadingArt = true
        defer { isLoadingArt = false }

        let library = ASCIILibrary.shared
        var results: [(id: String, art: String)] = []

        for artID in topic.relatedArtIDs {
            if let art = await library.art(id: artID) {
                results.append((id: artID, art: art))
            }
        }

        resolvedArt = results
    }

    // MARK: - Placeholder Parsing

    /// Segments of body text: either plain Markdown or an art placeholder.
    private enum BodySegment {
        case text(String)
        case artPlaceholder(String)
    }

    /// Parses `@{art:ID}` placeholders out of a body string.
    private func parsePlaceholders(in text: String) -> [BodySegment] {
        var segments: [BodySegment] = []
        guard
            let pattern = try? NSRegularExpression(
                pattern: "@\\{art:([^}]+)\\}"
            )
        else { return [.text(text)] }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var lastEnd = text.startIndex

        pattern.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match, let matchRange = Range(match.range, in: text) else { return }

            // Text before this match.
            if lastEnd < matchRange.lowerBound {
                let before = String(text[lastEnd..<matchRange.lowerBound])
                if !before.isEmpty {
                    segments.append(.text(before))
                }
            }

            // The art ID from capture group 1.
            if let artIDRange = Range(match.range(at: 1), in: text) {
                let artID = String(text[artIDRange])
                segments.append(.artPlaceholder(artID))
            }

            lastEnd = matchRange.upperBound
        }

        // Remaining text after the last placeholder.
        if lastEnd < text.endIndex {
            let remaining = String(text[lastEnd..<text.endIndex])
            if !remaining.isEmpty {
                segments.append(.text(remaining))
            }
        }

        return segments
    }

    // MARK: - Markdown Body Loading

    /// Loads the full `.md` body from the bundle for the given topic ID.
    ///
    /// Topic IDs follow the pattern `"category/topic-name"` (e.g. `"basics/drawing-shapes"`),
    /// which maps to a file at `9.2 ASCII art Help/basics/drawing-shapes.md` in the bundle.
    private func loadMarkdownBody(for topicID: String) -> String? {
        let components = topicID.split(separator: "/", maxSplits: 1)
        guard components.count == 2 else { return nil }

        let subdirectory = "9.2 ASCII art Help/" + components[0]
        let filename = String(components[1])

        guard
            let url = Bundle.main.url(
                forResource: filename,
                withExtension: "md",
                subdirectory: subdirectory
            )
        else {
            #if DEBUG
                print("[ASCIIArtHelp] Could not find .md file for topic: \(topicID)")
            #endif
            return nil
        }

        return try? String(contentsOf: url, encoding: .utf8)
    }
}
