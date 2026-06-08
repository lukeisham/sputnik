import Foundation
import SwiftUI

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
