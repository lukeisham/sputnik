import Foundation

/// A single slash-command entry for the universal auto-complete popup.
///
/// Commands are registered at launch by each module that supports them.
/// The `insert` string is substituted at the trigger point when the user
/// selects a command.
public struct SlashCommand: Sendable, Identifiable {
    /// Unique identifier, e.g. `"markdown.heading1"`.
    public let id: String

    /// Display label in the popup list, e.g. `"/heading1"`.
    public let label: String

    /// Short description shown alongside the label, e.g. `"H1 block"`.
    public let detail: String

    /// Section header for grouping, e.g. `"Markdown"`.
    public let category: String

    /// The text inserted at the trigger point when the command is selected.
    /// May include template placeholders.
    public let insert: String

    public init(id: String, label: String, detail: String, category: String, insert: String) {
        self.id = id
        self.label = label
        self.detail = detail
        self.category = category
        self.insert = insert
    }
}
