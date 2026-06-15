import AppKit
import SwiftUI

/// Shared colour palette with automatic light/dark resolution.
///
/// Colours are defined as SwiftUI `Color` values backed by `NSColor` asset-catalog
/// semantic colours where available, falling back to hard-coded light/dark pairs.
/// Resolution happens via the SwiftUI `colorScheme` environment value — no manual
/// refresh is required when the system appearance changes while the app is running.
///
/// **Contrast awareness:** Background colours that use bespoke values (e.g. terminal)
/// now branch on the **Increase Contrast** accessibility setting as well as light/dark
/// appearance, providing visibly higher-contrast variants when the user has that
/// setting enabled. Colours backed by system semantic colours (e.g. `.editorBackground`
/// via `NSColor.textBackgroundColor`) inherit Apple's contrast handling automatically.
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
    ///
    /// Uses the system semantic `NSColor.textBackgroundColor` — the standard text-editing
    /// surface background on macOS. This value automatically adapts to light/dark
    /// appearance **and** the Increase Contrast accessibility setting, so no bespoke
    /// contrast provider is needed.
    ///
    /// **Intent:** While the resulting colour (~0.99 white light / ~0.12 dark) closely
    /// matches the old hard-coded pair, the system colour may shift slightly across
    /// macOS releases. This is intentional — Sputnik follows the platform's lead.
    public static var editorBackground: Color { Color(NSColor.textBackgroundColor) }

    /// Ghost-text / inline suggestion foreground.
    public static var ghostText: Color { Color(NSColor.tertiaryLabelColor) }

    // MARK: - Minimap

    /// Minimap bar colour for plain text lines.
    public static var minimapPlain: Color {
        Color(light: Color(white: 0.55), dark: Color(white: 0.50))
    }

    /// Minimap bar colour for blank lines (dimmer than plain).
    public static var minimapBlank: Color {
        Color(light: Color(white: 0.35), dark: Color(white: 0.30))
    }

    /// Minimap bar colour for heading lines.
    public static var minimapHeading: Color {
        Color(
            light: Color(red: 0.15, green: 0.42, blue: 0.72),
            dark: Color(red: 0.35, green: 0.65, blue: 0.95))
    }

    /// Minimap bar colour for code/fenced-code-block lines.
    public static var minimapCode: Color {
        Color(
            light: Color(red: 0.62, green: 0.35, blue: 0.15),
            dark: Color(red: 0.85, green: 0.58, blue: 0.35))
    }

    /// Minimap bar colour for blockquote lines.
    public static var minimapQuote: Color {
        Color(
            light: Color(red: 0.55, green: 0.45, blue: 0.12),
            dark: Color(red: 0.78, green: 0.68, blue: 0.30))
    }

    /// Minimap bar colour for list-item lines.
    public static var minimapList: Color {
        Color(
            light: Color(red: 0.28, green: 0.55, blue: 0.18),
            dark: Color(red: 0.50, green: 0.78, blue: 0.40))
    }

    /// Minimap viewport-indicator tint.
    public static var minimapViewport: Color {
        Color(
            light: Color(white: 0.0, opacity: 0.28),
            dark: Color(white: 1.0, opacity: 0.28))
    }

    /// Primary accent for dynamic panel borders, active indicators, and toggle pills.
    /// Uses the system control accent colour.
    public static var accentPrimary: Color { Color(NSColor.controlAccentColor) }

    // MARK: - Terminal

    /// Terminal strip background.
    ///
    /// Keeps tuned values for ANSI legibility rather than using a system semantic colour,
    /// but the provider now honours **Increase Contrast** with visibly higher-contrast
    /// variants to satisfy the accessibility requirement.
    ///
    /// Contrast values:
    /// - Light normal: ~0.95 white (off-white strip)
    /// - Light high contrast: ~0.88 white (clearly darker separation from editor)
    /// - Dark normal: ~0.08 black (dark strip)
    /// - Dark high contrast: ~0.02 black (nearly pure black for max separation)
    public static var terminalBackground: Color {
        Color(
            light: Color(red: 0.95, green: 0.95, blue: 0.95),
            dark: Color(red: 0.08, green: 0.08, blue: 0.09),
            lightHighContrast: Color(red: 0.88, green: 0.88, blue: 0.88),
            darkHighContrast: Color(red: 0.02, green: 0.02, blue: 0.03)
        )
    }

    /// Default terminal foreground (ANSI normal text).
    ///
    /// Contrast values:
    /// - Light normal: ~0.10 black (near-black on near-white strip)
    /// - Light high contrast: pure black on higher-contrast strip
    /// - Dark normal: ~0.88 white (near-white on near-black strip)
    /// - Dark high contrast: ~0.96 white (brighter on nearly-pure-black strip)
    public static var terminalForeground: Color {
        Color(
            light: Color(red: 0.10, green: 0.10, blue: 0.10),
            dark: Color(red: 0.88, green: 0.88, blue: 0.88),
            lightHighContrast: Color(red: 0.0, green: 0.0, blue: 0.0),
            darkHighContrast: Color(red: 0.96, green: 0.96, blue: 0.96)
        )
    }
}

// MARK: - Helpers

extension Color {

    /// Creates a `Color` that resolves to `light` in light mode and `dark` in dark mode
    /// without requiring a view environment — backed by an `NSColor` dynamic provider.
    ///
    /// The provider queries the current `NSAppearance` and branches on `.aqua` vs
    /// `.darkAqua`. The **Increase Contrast** setting is **not** checked here; when
    /// high-contrast variants are required, use the four-argument overload instead.
    fileprivate init(light: Color, dark: Color) {
        self.init(
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(dark)
                    : NSColor(light)
            })
    }

    /// Creates a `Color` that branches on **both** light/dark appearance **and** the
    /// **Increase Contrast** accessibility setting.
    ///
    /// The dynamic `NSColor` provider matches against the full set of four appearance
    /// traits so the colour responds correctly when the user enables Increase Contrast
    /// in System Settings ▸ Accessibility ▸ Display.
    ///
    /// - Parameters:
    ///   - light: Colour in light mode, normal contrast.
    ///   - dark: Colour in dark mode, normal contrast.
    ///   - lightHighContrast: Colour in light mode with Increase Contrast on.
    ///   - darkHighContrast: Colour in dark mode with Increase Contrast on.
    fileprivate init(
        light: Color, dark: Color,
        lightHighContrast: Color, darkHighContrast: Color
    ) {
        self.init(
            NSColor(name: nil) { appearance in
                // Match against most-specific to least-specific.
                let traits: [NSAppearance.Name] = [
                    .accessibilityIncreasedContrastDarkAqua,
                    .accessibilityIncreasedContrastAqua,
                    .darkAqua,
                    .aqua,
                ]
                switch appearance.bestMatch(from: traits) {
                case .accessibilityIncreasedContrastDarkAqua:
                    return NSColor(darkHighContrast)
                case .accessibilityIncreasedContrastAqua:
                    return NSColor(lightHighContrast)
                case .darkAqua:
                    return NSColor(dark)
                default:  // .aqua or nil
                    return NSColor(light)
                }
            })
    }
}

// MARK: - NSAppearance.Name convenience

extension NSAppearance.Name {
    /// Accessibility increased contrast light appearance.
    /// Defined here because macOS does not expose it as a named constant
    /// in Swift — it is declared in the Objective-C header as
    /// `NSAccessibilityIncreasedContrastAquaAppearance`.
    fileprivate static let accessibilityIncreasedContrastAqua = NSAppearance.Name(
        "NSAccessibilityIncreasedContrastAquaAppearance")

    /// Accessibility increased contrast dark appearance.
    fileprivate static let accessibilityIncreasedContrastDarkAqua = NSAppearance.Name(
        "NSAccessibilityIncreasedContrastDarkAquaAppearance")
}
