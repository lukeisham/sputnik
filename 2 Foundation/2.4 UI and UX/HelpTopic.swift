import Foundation

/// The help topics surfaced from the Help menu.
///
/// Foundation owns the enum (a shared primitive) and the menu (module 2.6) sets
/// `AppState.requestedHelpTopic`; module 9 (Resources) observes that property and presents
/// the matching guide. Defining the type here keeps the menu and the resources module
/// decoupled (SR-1).
public enum HelpTopic: String, Codable, Sendable, CaseIterable, Identifiable {
    case sputnik
    case markdown
    case html
    case json
    case asciiArt
    case grammar

    public var id: String { rawValue }

    /// Human-readable title shown in the Help menu and the presented help surface.
    public var title: String {
        switch self {
        case .sputnik:  return "Sputnik Help"
        case .markdown: return "Markdown Help"
        case .html:     return "HTML Help"
        case .json:     return "JSON Help"
        case .asciiArt: return "ASCII Art Help"
        case .grammar:  return "Grammar Help"
        }
    }
}

// MARK: - Help Request

/// A single, shared route for revealing a help panel and (optionally) navigating it to a
/// specific topic.
///
/// Foundation owns this primitive (SR-1). The Help menu reveals a panel with `topicID == nil`
/// (overview); the editor's right-click "Look Up Help" reveals a panel *and* carries the
/// resolved `topicID` so the panel scrolls to the matching topic. Module 9 panels observe
/// `AppState.requestedHelpTarget` and navigate to `topicID` when present (resolves ISS-008).
public struct HelpRequest: Equatable, Sendable {
    /// Which help panel to reveal.
    public let kind: HelpTopic
    /// The topic to navigate to once revealed, or `nil` to show the panel's overview.
    public let topicID: String?

    public init(kind: HelpTopic, topicID: String? = nil) {
        self.kind = kind
        self.topicID = topicID
    }
}
