import Foundation

/// One of seven selectable debounce durations for auto-complete ghost-text suggestions.
///
/// Owned once in Foundation (SR-1) and consumed by each language provider (Markdown, HTML,
/// ASCII, spelling) via its own `SettingsStore` field so each provider gets an independent step.
/// `Codable` for persistence; `CaseIterable` for SwiftUI picker presentation.
public enum AutoCompleteDebounceStep: CaseIterable, Codable, Sendable {
    case instant
    case half
    case one
    case oneHalf
    case two
    case twoHalf
    case three

    /// The `TimeInterval` (seconds) represented by this step.
    public var timeInterval: TimeInterval {
        switch self {
        case .instant: return 0
        case .half: return 0.5
        case .one: return 1.0
        case .oneHalf: return 1.5
        case .two: return 2.0
        case .twoHalf: return 2.5
        case .three: return 3.0
        }
    }

    /// A human-readable label for UI display.
    public var label: String {
        switch self {
        case .instant: return "Instant"
        case .half: return "0.5 s"
        case .one: return "1 s"
        case .oneHalf: return "1.5 s"
        case .two: return "2 s"
        case .twoHalf: return "2.5 s"
        case .three: return "3 s"
        }
    }

    /// Default step: 0.5 s.
    public static let `default`: AutoCompleteDebounceStep = .half
}
