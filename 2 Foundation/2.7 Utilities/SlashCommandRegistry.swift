import Foundation
import Observation

/// The single registry of all slash commands available in Sputnik.
///
/// Modules register their commands at launch via `register(_:)`. The registry is
/// shared as a singleton so that the Text Editor, Scratchpad, and any future text
/// input surface all see the same command set without duplicating registration.
///
/// SW-1: `matches(for:)` is synchronous — filtering is an O(n) in-memory operation
/// and does not need async dispatch.
///
/// SR-1: Foundation owns the registry; each module owns its command content.
@Observable
@MainActor
public final class SlashCommandRegistry {

    /// All registered commands, keyed by category for popup sectioning.
    private var commandsByCategory: [String: [SlashCommand]] = [:]

    public init() {}

    /// Registers a batch of commands from a single module.
    ///
    /// - Parameter commands: The commands to add. Duplicate `id`s are silently
    ///   overwritten by the last-registered entry.
    public func register(_ commands: [SlashCommand]) {
        for cmd in commands {
            commandsByCategory[cmd.category, default: []].append(cmd)
        }
    }

    /// Returns all registered commands whose `label` or `detail` contains `prefix`,
    /// grouped by category. Case-insensitive.
    ///
    /// - Parameter prefix: The filter string (without the leading `/`).
    ///   An empty string returns every registered command.
    /// - Returns: Commands grouped by `category`, each group sorted by `label`.
    public func matches(for prefix: String) -> [(category: String, commands: [SlashCommand])] {
        let lower = prefix.lowercased()
        var result: [(String, [SlashCommand])] = []

        for (category, cmds) in commandsByCategory {
            let filtered = cmds.filter { cmd in
                lower.isEmpty
                    || cmd.label.lowercased().contains(lower)
                    || cmd.detail.lowercased().contains(lower)
            }
            if !filtered.isEmpty {
                result.append((category, filtered.sorted { lhs, rhs in lhs.label < rhs.label }))
            }
        }

        // Stable sort by category name.
        result.sort { a, b in a.0 < b.0 }
        return result
    }

    /// All registered flat commands (unfiltered).
    public var allCommands: [SlashCommand] {
        commandsByCategory.values.flatMap { $0 }.sorted { $0.label < $1.label }
    }
}
