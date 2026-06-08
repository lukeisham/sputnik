import Foundation

/// A lightweight RGBA colour that is safe to pass across concurrency boundaries.
///
/// Uses `Double` components (0.0–1.0) so no AppKit import is required at this layer.
/// Callers convert to `NSColor` or `Color` at the rendering boundary.
public struct TerminalColor: Sendable, Equatable, Hashable, Codable {
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
