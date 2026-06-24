import Foundation
import FoundationModule

/// Loads and matches the `special_elements.json` registry.
///
/// Thread-safe: actor isolation ensures one-time loading and safe concurrent access.
/// Decode is tolerant: a malformed entry is skipped with a logged warning; the rest load.
public actor SpecialElementRegistry {

    // MARK: - Singleton

    public static let shared = SpecialElementRegistry()

    // MARK: - State

    private var definitions: [String: SpecialElementDefinition] = [:]
    private var didLoad = false

    private init() {}

    // MARK: - Public API

    /// Returns all loaded definitions.
    public func allDefinitions() async -> [SpecialElementDefinition] {
        await ensureLoaded()
        return Array(definitions.values)
    }

    /// Direct fetch by definition id.
    public func definition(id: String) async -> SpecialElementDefinition? {
        await ensureLoaded()
        return definitions[id]
    }

    /// Resolves a special element definition from the two detection signals.
    ///
    /// Matching rules:
    /// - `syntaxTerm` must match at least one of an entry's `triggers.syntaxTerms` (exact, case-insensitive).
    /// - Among matching entries, heading-cued entries (non-empty `headingCues`) outrank generic ones (empty `headingCues`).
    /// - Within heading-cued entries, the one with the best fuzzy heading match wins.
    /// - If no heading-cued entry matches, the best generic entry wins.
    /// - Returns `nil` if no entry matches the syntax term at all.
    ///
    /// - Parameters:
    ///   - syntaxTerm: The detected structural signal (e.g. "table", "blockquote").
    ///   - contextHeading: The nearest heading above the selection, or `nil`.
    /// - Returns: The best-matching definition, or `nil`.
    public func resolve(syntaxTerm: String, contextHeading: String?) async
        -> SpecialElementDefinition?
    {
        await ensureLoaded()

        let lowerSyntax = syntaxTerm.lowercased()

        // Find all entries whose syntaxTerms contain the detected term.
        var headingCued: [(definition: SpecialElementDefinition, score: Double)] = []
        var generic: [SpecialElementDefinition] = []

        for def in definitions.values {
            guard def.triggers.syntaxTerms.contains(where: { $0.lowercased() == lowerSyntax })
            else {
                continue
            }

            if def.triggers.headingCues.isEmpty {
                generic.append(def)
            } else if let heading = contextHeading {
                let score = HeadingFuzzyMatcher.score(
                    query: heading, candidate: def.triggers.headingCues.joined(separator: " "))
                headingCued.append((def, score))
            }
        }

        // Heading-cued entries outrank generic ones.
        if let best = headingCued.sorted(by: { $0.score > $1.score }).first {
            return best.definition
        }

        // Fall back to the first generic entry matching the syntax term.
        return generic.first
    }

    // MARK: - Private

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true

        guard
            let url = Bundle.module.url(
                forResource: "special_elements",
                withExtension: "json",
                subdirectory: "9.8 Interaction"
            )
        else {
            #if DEBUG
                print("[SpecialElementRegistry] special_elements.json not found in bundle")
            #endif
            return
        }

        guard let data = try? Data(contentsOf: url) else {
            #if DEBUG
                print("[SpecialElementRegistry] Failed to load special_elements.json")
            #endif
            return
        }

        do {
            let container = try JSONDecoder().decode(
                SpecialElementRegistryContainer.self, from: data)
            var valid: [String: SpecialElementDefinition] = [:]
            for def in container.definitions {
                if valid[def.id] != nil {
                    #if DEBUG
                        print("[SpecialElementRegistry] Duplicate id '\(def.id)' — skipping")
                    #endif
                    continue
                }
                valid[def.id] = def
            }
            definitions = valid
        } catch {
            #if DEBUG
                print("[SpecialElementRegistry] Failed to decode special_elements.json: \(error)")
            #endif
        }
    }
}

// MARK: - Decoding container

private struct SpecialElementRegistryContainer: Codable {
    let definitions: [SpecialElementDefinition]

    enum CodingKeys: String, CodingKey {
        case definitions
    }
}
