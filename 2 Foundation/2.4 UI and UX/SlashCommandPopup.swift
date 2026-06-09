import SwiftUI

/// A floating command palette popup that displays a searchable, grouped list of
/// slash commands. Intended to be overlaid on top of a text input when the user
/// types `/`.
///
/// The popup presents a search field at the top, followed by a `List` grouped by
/// `category`. Tapping a row calls `onSelect` and dismisses. Pressing Escape
/// dismisses without selection.
///
/// ## Usage
///
/// ```swift
/// SlashCommandPopup(
///     commands: registry.allCommands,
///     onSelect: { command in handleInsert(command.insert) },
///     dismiss: { showPopup = false }
/// )
/// ```
///
/// The caller is responsible for filtering `commands` (e.g. via
/// `SlashCommandRegistry.matches(for:)`) and for positioning the popup frame.
public struct SlashCommandPopup: View {

    // MARK: - Public Properties

    private let commands: [SlashCommand]
    private let onSelect: (SlashCommand) -> Void
    private let dismiss: () -> Void

    // MARK: - Internal State

    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    /// Retains the local key-down monitor so it can be removed on disappear.
    /// `NSEvent.addLocalMonitorForEvents` returns an opaque `Any?`.
    @State private var escapeMonitor: Any?

    // MARK: - Initializers

    /// Creates a slash command popup.
    ///
    /// - Parameters:
    ///   - commands: All available slash commands. They are grouped by `category`
    ///     internally. Pass a pre-filtered array if you have already narrowed the
    ///     results (e.g. via `SlashCommandRegistry.matches(for:)`).
    ///   - onSelect: Called when the user selects a command.
    ///   - dismiss: Called when the popup should be dismissed (selection or Escape).
    public init(
        commands: [SlashCommand],
        onSelect: @escaping (SlashCommand) -> Void,
        dismiss: @escaping () -> Void
    ) {
        self.commands = commands
        self.onSelect = onSelect
        self.dismiss = dismiss
    }

    // MARK: - Grouping & Filtering

    /// All commands grouped by `category`, each group sorted by `label`.
    private var groupedByCategory: [(category: String, commands: [SlashCommand])] {
        Dictionary(grouping: commands) { $0.category }
            .map { (key: $0.key, commands: $0.value.sorted { $0.label < $1.label }) }
            .sorted { $0.category < $1.category }
    }

    /// Groups filtered by the current search text using case-insensitive prefix
    /// matching on both `label` and `detail`.
    private var filteredGroups: [(category: String, commands: [SlashCommand])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return groupedByCategory
        }
        return groupedByCategory.compactMap { category, cmds in
            let matched = cmds.filter { cmd in
                cmd.label.lowercased().hasPrefix(query)
                    || cmd.detail.lowercased().hasPrefix(query)
            }
            return matched.isEmpty ? nil : (category, matched)
        }
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
                .foregroundStyle(SputnikColor.separator)
            commandList
        }
        .frame(minWidth: 240, maxHeight: 300)
        .background(SputnikColor.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(SputnikColor.separator, lineWidth: 0.5)
        )
        .onAppear {
            isSearchFocused = true
            installEscapeMonitor()
        }
        .onDisappear {
            removeEscapeMonitor()
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: SputnikSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: SputnikFont.body))
                .foregroundStyle(SputnikColor.secondaryText)

            TextField("Filter commands…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: SputnikFont.body))
                .foregroundStyle(SputnikColor.primaryText)
                .focused($isSearchFocused)
        }
        .padding(.horizontal, SputnikSpacing.sm)
        .padding(.vertical, SputnikSpacing.xs)
    }

    // MARK: - Command List

    private var commandList: some View {
        List {
            ForEach(filteredGroups, id: \.category) { group in
                Section {
                    ForEach(group.commands) { command in
                        commandRow(command)
                    }
                } header: {
                    Text(group.category)
                        .font(.system(size: SputnikFont.caption, weight: .semibold))
                        .foregroundStyle(SputnikColor.secondaryText)
                        .textCase(.uppercase)
                }
            }
        }
        .listStyle(.plain)
    }

    /// Builds a single tappable row for a slash command.
    private func commandRow(_ command: SlashCommand) -> some View {
        Button {
            onSelect(command)
            dismiss()
        } label: {
            HStack(spacing: SputnikSpacing.sm) {
                Text(command.label)
                    .font(.system(size: SputnikFont.body, weight: .medium))
                    .foregroundStyle(SputnikColor.primaryText)
                    .lineLimit(1)

                Spacer()

                Text(command.detail)
                    .font(.system(size: SputnikFont.body))
                    .foregroundStyle(SputnikColor.secondaryText)
                    .lineLimit(1)
            }
            .padding(.vertical, SputnikSpacing.xs)
            .padding(.horizontal, SputnikSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Escape Key Handling

    /// Installs a local key-down monitor that intercepts Escape (keyCode 53)
    /// to dismiss the popup without making a selection.
    private func installEscapeMonitor() {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [dismiss] event in
            guard event.keyCode == 53 else { return event }
            dismiss()
            return nil
        }
        escapeMonitor = monitor
    }

    /// Removes the escape monitor when the view disappears.
    private func removeEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
        escapeMonitor = nil
    }
}

// MARK: - Preview

#Preview("SlashCommandPopup") {
    let sampleCommands = [
        SlashCommand(
            id: "markdown.h1", label: "/heading1", detail: "H1 block",
            category: "Markdown", insert: "# "),
        SlashCommand(
            id: "markdown.h2", label: "/heading2", detail: "H2 block",
            category: "Markdown", insert: "## "),
        SlashCommand(
            id: "markdown.h3", label: "/heading3", detail: "H3 block",
            category: "Markdown", insert: "### "),
        SlashCommand(
            id: "html.h1", label: "/h1", detail: "HTML H1 element",
            category: "HTML", insert: "<h1></h1>"),
        SlashCommand(
            id: "html.p", label: "/p", detail: "Paragraph element",
            category: "HTML", insert: "<p></p>"),
        SlashCommand(
            id: "ascii.cloud", label: "/cloud", detail: "Cloud ASCII art",
            category: "ASCII Art", insert: "☁︎"),
    ]

    SlashCommandPopup(
        commands: sampleCommands,
        onSelect: { print("Selected: \($0.label)") },
        dismiss: { print("Dismissed") }
    )
    .frame(width: 280)
    .padding()
}
