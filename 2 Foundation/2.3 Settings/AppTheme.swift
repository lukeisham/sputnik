import Foundation

/// The user's preferred colour-scheme override for the Sputnik UI.
public enum AppTheme: String, Codable, Sendable, CaseIterable {
    /// Always render in light mode regardless of the system setting.
    case light
    /// Always render in dark mode regardless of the system setting.
    case dark
    /// Follow the macOS system appearance.
    case system
}
