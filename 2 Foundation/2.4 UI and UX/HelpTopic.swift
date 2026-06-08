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
    case asciiArt
    case grammar

    public var id: String { rawValue }

    /// Human-readable title shown in the Help menu and the presented help surface.
    public var title: String {
        switch self {
        case .sputnik:  return "Sputnik Help"
        case .markdown: return "Markdown Help"
        case .html:     return "HTML Help"
        case .asciiArt: return "ASCII Art Help"
        case .grammar:  return "Grammar Help"
        }
    }
}
