import Foundation

/// A hand-maintained mirror of the keyboard shortcuts declared in the menu-bar command groups.
///
/// **This is a reference, not the binding source.** The real shortcuts live in
/// `FileMenuGroup`, `EditMenuGroup`, `ViewMenuGroup`, `FormatMenuGroup`, `HelpMenuGroup`,
/// `SputnikMenuGroup`, and `SputnikCommands.TerminalIntegrationCommands`.
/// If a menu shortcut changes, this catalog must be updated to match.
///
/// Owned by Foundation 2.0 (App Overview) because it is a shared reference list
/// with no per-module coupling (SR-1).

// MARK: - Shortcut entry

/// A single keyboard shortcut entry displayed in the Settings > Shortcuts tab.
public struct ShortcutEntry: Identifiable {
    public let id = UUID()
    /// Human-readable command name (e.g. "Save", "Toggle File Tree").
    public let title: String
    /// Human-readable key combination (e.g. "⌘S", "⌥⌘1").
    public let keys: String
    /// Menu group the shortcut belongs to (e.g. "File", "Edit").
    public let group: String

    public init(title: String, keys: String, group: String) {
        self.title = title
        self.keys = keys
        self.group = group
    }
}

// MARK: - Catalog

/// The single, curated catalogue of every keyboard shortcut available in Sputnik.
public enum KeyboardShortcutCatalog {

    /// Every shortcut in the app, grouped by menu.
    public static let all: [ShortcutEntry] = _all

    /// Shortcuts grouped for display in the Settings tab.
    public static var grouped: [(group: String, entries: [ShortcutEntry])] {
        let groups = Dictionary(grouping: all, by: \.group)
        // Stable ordering: Sputnik → File → Edit → Terminal → Format → View → Help
        let order = ["Sputnik", "File", "Edit", "Terminal", "Format", "View", "Help"]
        return order.compactMap { key in
            groups[key].map { (group: key, entries: $0.sorted { $0.title < $1.title }) }
        }
    }
}

// MARK: - Private catalogue data

private let _all: [ShortcutEntry] = [
    // ── Sputnik ──
    ShortcutEntry(title: "Settings…", keys: "⌘,", group: "Sputnik"),
    ShortcutEntry(title: "Hide Sputnik", keys: "⌘H", group: "Sputnik"),
    ShortcutEntry(title: "Hide Others", keys: "⌥⌘H", group: "Sputnik"),
    ShortcutEntry(title: "Quit Sputnik", keys: "⌘Q", group: "Sputnik"),

    // ── File ──
    ShortcutEntry(title: "New Tab", keys: "⌘T", group: "File"),
    ShortcutEntry(title: "New Window", keys: "⇧⌘N", group: "File"),
    ShortcutEntry(title: "Open…", keys: "⌘O", group: "File"),
    ShortcutEntry(title: "Save As Template…", keys: "⌃⌘S", group: "File"),
    ShortcutEntry(title: "Close Tab", keys: "⌘W", group: "File"),
    ShortcutEntry(title: "Close Window", keys: "⇧⌘W", group: "File"),
    ShortcutEntry(title: "Save", keys: "⌘S", group: "File"),
    ShortcutEntry(title: "Save As…", keys: "⇧⌘S", group: "File"),
    ShortcutEntry(title: "Render as HTML", keys: "⌥⌘P", group: "File"),
    ShortcutEntry(title: "Print…", keys: "⌘P", group: "File"),

    // ── Edit ──
    ShortcutEntry(title: "Undo", keys: "⌘Z", group: "Edit"),
    ShortcutEntry(title: "Redo", keys: "⇧⌘Z", group: "Edit"),
    ShortcutEntry(title: "Cut", keys: "⌘X", group: "Edit"),
    ShortcutEntry(title: "Copy", keys: "⌘C", group: "Edit"),
    ShortcutEntry(title: "Paste", keys: "⌘V", group: "Edit"),
    ShortcutEntry(title: "Select All", keys: "⌘A", group: "Edit"),
    ShortcutEntry(title: "Find…", keys: "⌘F", group: "Edit"),
    ShortcutEntry(title: "Find and Replace…", keys: "⌥⌘F", group: "Edit"),
    ShortcutEntry(title: "Find Next", keys: "⌘G", group: "Edit"),
    ShortcutEntry(title: "Find Previous", keys: "⇧⌘G", group: "Edit"),
    ShortcutEntry(title: "Check Now", keys: "⌘;", group: "Edit"),
    ShortcutEntry(title: "Interact with", keys: "⌘I", group: "Edit"),
    ShortcutEntry(title: "Render as JSON", keys: "⌃⌘J", group: "Edit"),

    // ── Terminal ──
    ShortcutEntry(title: "Send Selection to Terminal", keys: "⌃⌘E", group: "Terminal"),
    ShortcutEntry(title: "Run Current File in Terminal", keys: "⌃⌘R", group: "Terminal"),
    ShortcutEntry(title: "Insert Terminal Selection", keys: "⌃⌘I", group: "Terminal"),
    ShortcutEntry(title: "Insert Last Command Output", keys: "⌃⌘O", group: "Terminal"),
    ShortcutEntry(title: "New Terminal Tab", keys: "⌘T", group: "Terminal"),

    // ── Format ──
    ShortcutEntry(title: "ASCII Studio", keys: "⌥⌘A", group: "Format"),

    // ── View ──
    ShortcutEntry(title: "Toggle File Tree", keys: "⌥⌘1", group: "View"),
    ShortcutEntry(title: "Toggle Markdown Preview", keys: "⌥⌘2", group: "View"),
    ShortcutEntry(title: "Toggle HTML Preview", keys: "⌥⌘3", group: "View"),
    ShortcutEntry(title: "Toggle Terminal", keys: "⌥⌘4", group: "View"),
    ShortcutEntry(title: "Scratchpad", keys: "⇧⌘K", group: "View"),
    ShortcutEntry(title: "Focus: Editor", keys: "⌃⌘E", group: "View"),
    ShortcutEntry(title: "Focus: Reader", keys: "⌃⌘R", group: "View"),
    ShortcutEntry(title: "Focus Next Panel", keys: "⌃⇥", group: "View"),
    ShortcutEntry(title: "Focus Previous Panel", keys: "⌃⇧⇥", group: "View"),
    ShortcutEntry(title: "Focus: Terminal", keys: "⌃⌘T", group: "View"),
    ShortcutEntry(title: "Focus: File Tree Panel", keys: "⌃⌘F", group: "View"),
    ShortcutEntry(title: "Restore Default Layout", keys: "⌃⌘0", group: "View"),
    ShortcutEntry(title: "Minimap", keys: "⌃⌘5", group: "View"),

    // ── Help ──
    ShortcutEntry(title: "Sputnik Help", keys: "⌘?", group: "Help"),
]
