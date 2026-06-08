import Foundation
import SwiftUI

/// A lightweight RGBA colour that is safe to pass across concurrency boundaries.
///
/// Uses `Double` components (0.0–1.0) so no AppKit import is required at this layer.
/// Callers convert to `NSColor` or `Color` at the rendering boundary.
public struct TerminalColor: Sendable, Equatable, Hashable {
    public var red:   Double
    public var green: Double
    public var blue:  Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red   = red
        self.green = green
        self.blue  = blue
        self.alpha = alpha
    }
}

public extension TerminalColor {
    static let black   = TerminalColor(red: 0.00, green: 0.00, blue: 0.00)
    static let red     = TerminalColor(red: 0.80, green: 0.11, blue: 0.11)
    static let green   = TerminalColor(red: 0.13, green: 0.67, blue: 0.20)
    static let yellow  = TerminalColor(red: 0.90, green: 0.75, blue: 0.11)
    static let blue    = TerminalColor(red: 0.18, green: 0.46, blue: 0.80)
    static let magenta = TerminalColor(red: 0.69, green: 0.18, blue: 0.69)
    static let cyan    = TerminalColor(red: 0.17, green: 0.67, blue: 0.73)
    static let white   = TerminalColor(red: 0.88, green: 0.88, blue: 0.88)

    static let brightBlack   = TerminalColor(red: 0.33, green: 0.33, blue: 0.33)
    static let brightRed     = TerminalColor(red: 1.00, green: 0.30, blue: 0.30)
    static let brightGreen   = TerminalColor(red: 0.30, green: 0.90, blue: 0.30)
    static let brightYellow  = TerminalColor(red: 1.00, green: 0.95, blue: 0.35)
    static let brightBlue    = TerminalColor(red: 0.40, green: 0.60, blue: 1.00)
    static let brightMagenta = TerminalColor(red: 0.90, green: 0.40, blue: 0.90)
    static let brightCyan    = TerminalColor(red: 0.40, green: 0.90, blue: 0.95)
    static let brightWhite   = TerminalColor(red: 1.00, green: 1.00, blue: 1.00)
}

/// Customisation profile for the terminal panel.
///
/// Ships with built-in defaults (ISS-002: `SettingsStore` (2.3) does not yet expose
/// terminal-specific fields). Once 2.3 adds `terminalProfile`, `TerminalView` should
/// read from `@Environment(SettingsStore.self)` instead of constructing a default here.
public struct TerminalProfile: Sendable, Equatable {

    /// Monospace font name (must resolve to an NSFont on the target machine).
    public var fontName: String

    /// Font size in points.
    public var fontSize: Double

    /// Default foreground colour (ANSI "normal" text).
    public var foreground: TerminalColor

    /// Default background colour.
    public var background: TerminalColor

    /// ANSI 16-colour palette: indices 0–7 normal, 8–15 bright.
    public var ansiPalette: [TerminalColor]

    /// Maximum number of lines held in the scrollback ring buffer (SR-3).
    public var scrollbackLineLimit: Int

    public init(
        fontName: String = "Menlo",
        fontSize: Double = 13.0,
        foreground: TerminalColor = TerminalColor(red: 0.88, green: 0.88, blue: 0.88),
        background: TerminalColor = TerminalColor(red: 0.08, green: 0.08, blue: 0.09),
        ansiPalette: [TerminalColor] = TerminalProfile.defaultPalette,
        scrollbackLineLimit: Int = 5_000
    ) {
        self.fontName           = fontName
        self.fontSize           = fontSize
        self.foreground         = foreground
        self.background         = background
        self.ansiPalette        = ansiPalette
        self.scrollbackLineLimit = scrollbackLineLimit
    }

    /// SwiftUI `Color` for use in SwiftUI views (avoids `NSColor` in the view layer).
    public var swiftUIBackground: Color {
        Color(red: background.red, green: background.green, blue: background.blue)
            .opacity(background.alpha)
    }

    /// The default 16-colour ANSI palette (normal 0–7, bright 8–15).
    public static let defaultPalette: [TerminalColor] = [
        .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white,
        .brightBlack, .brightRed, .brightGreen, .brightYellow,
        .brightBlue, .brightMagenta, .brightCyan, .brightWhite,
    ]

    /// A ready-to-use default profile with no dependencies on `SettingsStore`.
    public static let `default` = TerminalProfile()
}
