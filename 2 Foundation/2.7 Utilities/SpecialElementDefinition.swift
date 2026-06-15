import Foundation

// MARK: - Element Triggers

/// The two-signal trigger criteria that define when a special element is recognised.
public struct ElementTriggers: Codable, Sendable {
    /// Structural pattern terms that fire detection (e.g. `["table", "row"]`).
    /// At least one must match the detected syntax term.
    public let syntaxTerms: [String]
    /// Contextual heading cues (e.g. `["Sentence parser", "sentence parser"]`).
    /// Matched fuzzily against the nearest heading above the selection.
    /// When empty, the definition matches any heading (generic/fallback).
    public let headingCues: [String]

    public init(syntaxTerms: [String], headingCues: [String] = []) {
        self.syntaxTerms = syntaxTerms
        self.headingCues = headingCues
    }
}

// MARK: - Resource Lookup

/// Named resource lookups that fill a slot from an existing index call.
public enum ResourceLookup: String, Codable, Sendable {
    /// `GrammarHelpIndex.searchByTerm(selection, preferStructural: false)` — lexical grammar topic.
    case lexicalDefinition = "lexicalDefinition"
    /// `GrammarHelpIndex.searchByTerm(selection, preferStructural: true)` — structural grammar topic.
    case structuralAnalysis = "structuralAnalysis"
    /// Best match from the Markdown help index.
    case markdownTopic = "markdownTopic"
    /// Best match from the HTML help index.
    case htmlTopic = "htmlTopic"
    /// Best match from the ASCII art help index.
    case asciiTopic = "asciiTopic"
    /// Best match from the JSON help index.
    case jsonTopic = "jsonTopic"
}

// MARK: - Slot Source

/// The source of content for a single slot in a special element definition.
public enum SlotSource: Codable, Sendable {
    /// Content left empty for the user to fill.
    case userContent
    /// Content filled from a named resource index lookup.
    case resource(lookup: ResourceLookup)

    // MARK: Codable
    private enum CodingKeys: String, CodingKey {
        case type, lookup
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "userContent":
            self = .userContent
        case "resource":
            let lookup = try container.decode(ResourceLookup.self, forKey: .lookup)
            self = .resource(lookup: lookup)
        default:
            // Tolerant decode: unknown source becomes userContent (log warning).
            #if DEBUG
                print(
                    "[SpecialElementDefinition] Unknown slot source '\(type)' — degrading to userContent"
                )
            #endif
            self = .userContent
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .userContent:
            try container.encode("userContent", forKey: .type)
        case .resource(let lookup):
            try container.encode("resource", forKey: .type)
            try container.encode(lookup, forKey: .lookup)
        }
    }
}

// MARK: - Element Slot

/// A single slot in a special element definition — one row/item in the template.
public struct ElementSlot: Codable, Sendable {
    /// The role/semantic name of this slot (e.g. `"sentence"`, `"lexical"`, `"structural"`).
    public let role: String
    /// The display label shown in the UI (e.g. "Your Sentence", "Lexical Analysis").
    public let label: String
    /// The source of content for this slot.
    public let source: SlotSource

    public init(role: String, label: String, source: SlotSource) {
        self.role = role
        self.label = label
        self.source = source
    }
}

// MARK: - Special Element Definition

/// A declarative registry entry describing one type of special element.
///
/// Foundation owns the shape (SR-1); the actual instances are authored in
/// `special_elements.json` and live in module 9.8.
public struct SpecialElementDefinition: Codable, Sendable {
    /// Unique identifier (e.g. `"sentence-parser"`, `"markdown-table-generic"`).
    public let id: String
    /// Human-readable name shown in the menu (e.g. "Sentence Parser").
    public let displayName: String
    /// The resource language used for slot lookups (e.g. `.grammar`, `.markdown`).
    public let resourceLanguage: WritingAssistLanguage
    /// The container kind — determines insertion mechanics.
    public let container: SpecialElementKind
    /// The two-signal trigger criteria.
    public let triggers: ElementTriggers
    /// Ordered list of slots. Each slot becomes one item in the inserted template.
    public let slots: [ElementSlot]

    public init(
        id: String,
        displayName: String,
        resourceLanguage: WritingAssistLanguage,
        container: SpecialElementKind,
        triggers: ElementTriggers,
        slots: [ElementSlot]
    ) {
        self.id = id
        self.displayName = displayName
        self.resourceLanguage = resourceLanguage
        self.container = container
        self.triggers = triggers
        self.slots = slots
    }
}
