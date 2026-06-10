import Foundation
import SwiftUI

/// RGBA color for terminal rendering — used in profiles, ANSI palette, and NSColor conversions.
public struct TerminalColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    // Standard ANSI 16-colour palette
    public static let black = TerminalColor(red: 0.0, green: 0.0, blue: 0.0)
    public static let red = TerminalColor(red: 0.8, green: 0.0, blue: 0.0)
    public static let green = TerminalColor(red: 0.0, green: 0.8, blue: 0.0)
    public static let yellow = TerminalColor(red: 0.8, green: 0.8, blue: 0.0)
    public static let blue = TerminalColor(red: 0.0, green: 0.0, blue: 0.8)
    public static let magenta = TerminalColor(red: 0.8, green: 0.0, blue: 0.8)
    public static let cyan = TerminalColor(red: 0.0, green: 0.8, blue: 0.8)
    public static let white = TerminalColor(red: 0.8, green: 0.8, blue: 0.8)

    public static let brightBlack = TerminalColor(red: 0.5, green: 0.5, blue: 0.5)
    public static let brightRed = TerminalColor(red: 1.0, green: 0.5, blue: 0.5)
    public static let brightGreen = TerminalColor(red: 0.5, green: 1.0, blue: 0.5)
    public static let brightYellow = TerminalColor(red: 1.0, green: 1.0, blue: 0.5)
    public static let brightBlue = TerminalColor(red: 0.5, green: 0.5, blue: 1.0)
    public static let brightMagenta = TerminalColor(red: 1.0, green: 0.5, blue: 1.0)
    public static let brightCyan = TerminalColor(red: 0.5, green: 1.0, blue: 1.0)
    public static let brightWhite = TerminalColor(red: 1.0, green: 1.0, blue: 1.0)
}

/// Customisation profile for the terminal panel.
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
