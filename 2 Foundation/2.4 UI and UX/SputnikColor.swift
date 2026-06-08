import SwiftUI
import AppKit

/// Shared colour palette with automatic light/dark resolution.
///
/// Colours are defined as SwiftUI `Color` values backed by `NSColor` asset-catalog
/// semantic colours where available, falling back to hard-coded light/dark pairs.
/// Resolution happens via the SwiftUI `colorScheme` environment value — no manual
/// refresh is required when the system appearance changes while the app is running.
public enum SputnikColor {

    // MARK: - Backgrounds

    /// Primary window/panel background.
    public static var background: Color { Color(NSColor.windowBackgroundColor) }

    /// Secondary surface (sidebars, header strips).
    public static var secondaryBackground: Color { Color(NSColor.controlBackgroundColor) }

    /// Hover/selection highlight background.
    public static var selectionBackground: Color { Color(NSColor.selectedContentBackgroundColor) }

    // MARK: - Text

    /// Primary body text.
    public static var primaryText: Color { Color(NSColor.labelColor) }

    /// Secondary / metadata text.
    public static var secondaryText: Color { Color(NSColor.secondaryLabelColor) }

    /// Placeholder / disabled text.
    public static var tertiaryText: Color { Color(NSColor.tertiaryLabelColor) }

    // MARK: - Separators

    /// Thin divider between panels or sections.
    public static var separator: Color { Color(NSColor.separatorColor) }

    // MARK: - Accent

    /// System accent colour (used for highlights, active indicators, focus rings).
    public static var accent: Color { Color(NSColor.controlAccentColor) }

    // MARK: - Editor surface

    /// The editor text area background (distinct from the window background).
    public static var editorBackground: Color {
        Color(light: Color(red: 0.99, green: 0.99, blue: 0.99),
              dark:  Color(red: 0.12, green: 0.12, blue: 0.13))
    }

    /// Ghost-text / inline suggestion foreground.
    public static var ghostText: Color { Color(NSColor.tertiaryLabelColor) }

    // MARK: - Terminal

    /// Terminal strip background.
    public static var terminalBackground: Color {
        Color(light: Color(red: 0.95, green: 0.95, blue: 0.95),
              dark:  Color(red: 0.08, green: 0.08, blue: 0.09))
    }

    /// Default terminal foreground (ANSI normal text).
    public static var terminalForeground: Color {
        Color(light: Color(red: 0.10, green: 0.10, blue: 0.10),
              dark:  Color(red: 0.88, green: 0.88, blue: 0.88))
    }
}

// MARK: - Helpers

private extension Color {
    /// Creates a `Color` that resolves to `light` in light mode and `dark` in dark mode
    /// without requiring a view environment — backed by an `NSColor` dynamic provider.
    init(light: Color, dark: Color) {
        self.init(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        })
    }
}
