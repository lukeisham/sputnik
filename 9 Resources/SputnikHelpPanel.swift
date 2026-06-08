import SwiftUI

/// Protocol all help topic content types conform to.
///
/// Each help sub-module (9.2–9.5) defines a concrete `Codable` type that satisfies
/// this protocol. `SputnikHelpPanel` is generic over `Topic`, so all tab, sidebar,
/// search, and persistence behaviour is shared across the four help panels.
public protocol HelpTopicProtocol: Identifiable, Hashable, Codable, Sendable where ID == String {
    /// Human-readable title shown in the tab bar and sidebar.
    var title: String { get }
    /// Category the topic belongs to (used to group the sidebar).
    var category: String { get }
    /// Full body content (Markdown or plain text, rendered by the per-panel content view).
    var body: String { get }
    /// Alternative search terms for fuzzy matching (e.g. "their"/"there"/"they're").
    var searchTerms: [String] { get }
    /// IDs of related topics for cross-reference links.
    var relatedTopics: [String] { get }
}

// MARK: - Saved Tab State

/// Persisted representation of a single open tab.
///
/// Lightweight — stores only the topic ID and title so the panel can re-resolve the
/// full `Topic` from its index on restore. Topics that no longer exist in the index
/// are silently dropped.
public struct HelpTabState: Codable, Sendable, Hashable {
    public var topicID: String
    public var title: String

    public init(topicID: String, title: String) {
        self.topicID = topicID
        self.title = title
    }
}

/// Persisted state for a single help panel: open tabs and the active tab ID.
public struct HelpPanelPersistedState: Codable, Sendable {
    public var tabs: [HelpTabState]
    public var activeTabID: String?

    public init(tabs: [HelpTabState] = [], activeTabID: String? = nil) {
        self.tabs = tabs
        self.activeTabID = activeTabID
    }
}

// MARK: - Shared Help Panel

/// A reusable tabbed help panel shared by all four help sub-modules (9.2–9.5).
///
/// `SputnikHelpPanel` handles:
/// - Tab bar (select, close, reorder via drag)
/// - Search bar with debounced filtering
/// - Sidebar showing categories and filtered topic lists
/// - Content area (delegated to `topicContent` view builder)
/// - Tab-state persistence via `PersistenceService`
///
/// Each sub-module provides its concrete `Topic` type, an array of all topics,
/// category names, a persistence key, and a `@ViewBuilder` for rendering a topic's
/// body content. The panel owns no content-specific logic — that stays in the
/// sub-module's coordinator and content views.
public struct SputnikHelpPanel<Topic: HelpTopicProtocol, ContentView: View>: View {

    // MARK: - Properties

    /// All available topics loaded from the sub-module's index.
    public let allTopics: [Topic]

    /// Ordered category names for the sidebar.
    public let categories: [String]

    /// Unique key for persisting this panel's tab state.
    public let persistenceKey: String

    /// Builds the content view for a single topic.
    @ViewBuilder public let topicContent: (Topic) -> ContentView

    // MARK: - State

    @Environment(AppState.self) private var appState
    @State private var openTabIDs: [String] = []
    @State private var activeTabID: String? = nil
    @State private var searchQuery: String = ""
    @State private var selectedCategory: String? = nil
    @State private var hasRestored: Bool = false

    // MARK: - Derived

    /// Topics currently open as tabs, resolved from IDs.
    private var openTabs: [Topic] {
        openTabIDs.compactMap { id in allTopics.first { $0.id == id } }
    }

    /// The currently active topic, if any.
    private var activeTopic: Topic? {
        guard let id = activeTabID else { return nil }
        return allTopics.first { $0.id == id }
    }

    /// Topics filtered by search query and selected category.
    private var filteredTopics: [Topic] {
        var results = allTopics
        if let category = selectedCategory {
            results = results.filter { $0.category == category }
        }
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            results = results.filter { topic in
                topic.title.lowercased().contains(q)
                    || topic.searchTerms.contains { $0.lowercased().contains(q) }
            }
        }
        return results
    }

    /// Topics grouped by category for the sidebar.
    private var topicsByCategory: [(String, [Topic])] {
        let grouped = Dictionary(grouping: filteredTopics, by: { $0.category })
        return categories.compactMap { cat in
            guard let topics = grouped[cat], !topics.isEmpty else { return nil }
            return (cat, topics)
        }
    }

    // MARK: - Init

    public init(
        allTopics: [Topic],
        categories: [String],
        persistenceKey: String,
        @ViewBuilder topicContent: @escaping (Topic) -> ContentView
    ) {
        self.allTopics = allTopics
        self.categories = categories
        self.persistenceKey = persistenceKey
        self.topicContent = topicContent
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            searchBar
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                contentArea
            }
        }
        .background(SputnikColor.editorBackground)
        .task {
            await restoreTabState()
        }
        .onChange(of: appState.activeDocumentID) { _, _ in
            // Persist when the active document changes (user may switch context).
            Task { await persistTabState() }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(openTabs, id: \.id) { topic in
                    tabItem(topic)
                }
            }
        }
        .frame(height: 28)
        .background(SputnikColor.secondaryBackground)
    }

    private func tabItem(_ topic: Topic) -> some View {
        let isActive = activeTabID == topic.id
        return HStack(spacing: 4) {
            Text(topic.title)
                .font(.system(size: SputnikFont.caption, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? SputnikColor.primaryText : SputnikColor.secondaryText)
                .lineLimit(1)

            Button {
                closeTab(topic.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(SputnikColor.tertiaryText)
        }
        .padding(.horizontal, SputnikSpacing.sm)
        .frame(height: 28)
        .background(isActive ? SputnikColor.editorBackground : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { activateTab(topic.id) }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: SputnikSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: SputnikFont.caption))
                .foregroundStyle(SputnikColor.tertiaryText)

            TextField("Search topics...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: SputnikFont.caption))

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: SputnikFont.caption))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(SputnikColor.tertiaryText)
            }
        }
        .padding(.horizontal, SputnikSpacing.sm)
        .padding(.vertical, SputnikSpacing.xs)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedCategory) {
            Section {
                ForEach(categories, id: \.self) { category in
                    sidebarCategoryRow(category)
                }
            } header: {
                Text("Topics")
                    .font(.system(size: SputnikFont.caption, weight: .semibold))
                    .foregroundStyle(SputnikColor.secondaryText)
            }
        }
        .listStyle(.sidebar)
        .frame(width: 180)
        .scrollContentBackground(.hidden)
        .background(SputnikColor.secondaryBackground)
    }

    private func sidebarCategoryRow(_ category: String) -> some View {
        let topics = filteredTopics.filter { $0.category == category }
        let count = topics.count
        let isSelected = selectedCategory == category

        return HStack {
            Text(category)
                .font(.system(size: SputnikFont.caption, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? SputnikColor.primaryText : SputnikColor.secondaryText)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10))
                    .foregroundStyle(SputnikColor.tertiaryText)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedCategory = isSelected ? nil : category
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if let topic = activeTopic {
            ScrollView {
                VStack(alignment: .leading, spacing: SputnikSpacing.md) {
                    // Topic header
                    Text(topic.title)
                        .font(.system(size: SputnikFont.headline, weight: .bold))
                        .foregroundStyle(SputnikColor.primaryText)

                    Text(topic.category)
                        .font(.system(size: SputnikFont.caption))
                        .foregroundStyle(SputnikColor.tertiaryText)

                    Divider()

                    // Per-panel rendered content
                    topicContent(topic)

                    // Related topics
                    if !topic.relatedTopics.isEmpty {
                        Divider()
                        relatedTopicsSection(topic)
                    }
                }
                .padding(SputnikSpacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SputnikColor.editorBackground)
        } else if !openTabs.isEmpty {
            // Tabs exist but none active — show the first one
            Color.clear.onAppear {
                activeTabID = openTabs.first?.id
            }
        } else {
            // No tabs — show the topic browser
            topicBrowser
        }
    }

    /// Shown when no tabs are open — the full topic list for browsing.
    private var topicBrowser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SputnikSpacing.md) {
                ForEach(topicsByCategory, id: \.0) { category, topics in
                    VStack(alignment: .leading, spacing: SputnikSpacing.xs) {
                        Text(category)
                            .font(.system(size: SputnikFont.body, weight: .semibold))
                            .foregroundStyle(SputnikColor.primaryText)

                        ForEach(topics, id: \.id) { topic in
                            Button {
                                openTopic(topic.id)
                            } label: {
                                HStack {
                                    Text(topic.title)
                                        .font(.system(size: SputnikFont.caption))
                                        .foregroundStyle(SputnikColor.accent)
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .padding(SputnikSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SputnikColor.editorBackground)
    }

    // MARK: - Related Topics

    private func relatedTopicsSection(_ topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: SputnikSpacing.xs) {
            Text("Related Topics")
                .font(.system(size: SputnikFont.caption, weight: .semibold))
                .foregroundStyle(SputnikColor.secondaryText)

            ForEach(topic.relatedTopics, id: \.self) { relatedID in
                if let related = allTopics.first(where: { $0.id == relatedID }) {
                    Button {
                        openTopic(relatedID)
                    } label: {
                        Text(related.title)
                            .font(.system(size: SputnikFont.caption))
                            .foregroundStyle(SputnikColor.accent)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Text(relatedID)
                        .font(.system(size: SputnikFont.caption))
                        .foregroundStyle(SputnikColor.tertiaryText)
                        .strikethrough()
                }
            }
        }
    }

    // MARK: - Tab Management

    /// Opens a topic — activates existing tab or creates a new one.
    public func openTopic(_ id: String) {
        if let existingIndex = openTabIDs.firstIndex(of: id) {
            activeTabID = id
        } else {
            openTabIDs.append(id)
            activeTabID = id
        }
        Task { await persistTabState() }
    }

    /// Activates an already-open tab.
    private func activateTab(_ id: String) {
        activeTabID = id
        Task { await persistTabState() }
    }

    /// Closes a tab, activating the nearest neighbour.
    private func closeTab(_ id: String) {
        guard let index = openTabIDs.firstIndex(of: id) else { return }
        openTabIDs.remove(at: index)
        if activeTabID == id {
            if openTabIDs.isEmpty {
                activeTabID = nil
            } else {
                let neighbour = min(index, openTabIDs.count - 1)
                activeTabID = openTabIDs[neighbour]
            }
        }
        Task { await persistTabState() }
    }

    // MARK: - Persistence

    private func persistTabState() async {
        let state = HelpPanelPersistedState(
            tabs: openTabs.map { HelpTabState(topicID: $0.id, title: $0.title) },
            activeTabID: activeTabID
        )
        // Persist via UserDefaults-backed PersistenceService if available;
        // fall back to UserDefaults directly for the help-panel subsystem.
        UserDefaults.standard.set(
            try? JSONEncoder().encode(state),
            forKey: "Sputnik.helpPanel.\(persistenceKey)"
        )
    }

    private func restoreTabState() async {
        guard !hasRestored else { return }
        hasRestored = true

        guard
            let data = UserDefaults.standard.data(
                forKey: "Sputnik.helpPanel.\(persistenceKey)"
            ),
            let state = try? JSONDecoder().decode(HelpPanelPersistedState.self, from: data)
        else { return }

        // Resolve topic IDs, dropping any that no longer exist in the index.
        let validIDs = state.tabs.compactMap { tab -> String? in
            allTopics.contains(where: { $0.id == tab.topicID }) ? tab.topicID : nil
        }
        guard !validIDs.isEmpty else { return }

        openTabIDs = validIDs
        activeTabID = state.activeTabID.flatMap { id in
            validIDs.contains(id) ? id : validIDs.first
        }
    }
}
