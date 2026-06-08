import Foundation

/// How a terminal cell's foreground or background colour is specified.
public enum CellColor: Sendable, Equatable, Hashable {
    /// Inherit the profile's default foreground or background.
    case `default`
    /// One of the 16 ANSI palette indices (0–15).
    case ansi(UInt8)
    /// 256-colour palette index (0–255).
    case palette(UInt8)
    /// True-colour (24-bit RGB) value, components 0.0–1.0.
    case rgb(Double, Double, Double)
}

/// Visual style flags for a single terminal cell.
public struct CellStyle: Sendable, Equatable {
    public var bold:          Bool
    public var dim:           Bool
    public var italic:        Bool
    public var underline:     Bool
    public var blink:         Bool
    public var inverse:       Bool
    public var strikethrough: Bool

    public init(
        bold: Bool = false,
        dim: Bool = false,
        italic: Bool = false,
        underline: Bool = false,
        blink: Bool = false,
        inverse: Bool = false,
        strikethrough: Bool = false
    ) {
        self.bold          = bold
        self.dim           = dim
        self.italic        = italic
        self.underline     = underline
        self.blink         = blink
        self.inverse       = inverse
        self.strikethrough = strikethrough
    }

    /// All attributes reset to defaults (plain text).
    public static let plain = CellStyle()
}

/// A single rendered character cell in the terminal grid.
///
/// Every property is value-typed and `Sendable` so a grid snapshot can be
/// passed from the emulator actor to `@MainActor` without copying anything
/// non-Sendable (SW-1, SR-4).
public struct ScreenCell: Sendable, Equatable {
    /// The Unicode scalar displayed in this cell. Space (`" "`) for an empty cell.
    public var character:  Character
    public var foreground: CellColor
    public var background: CellColor
    public var style:      CellStyle

    public init(
        character:  Character  = " ",
        foreground: CellColor  = .default,
        background: CellColor  = .default,
        style:      CellStyle  = .plain
    ) {
        self.character  = character
        self.foreground = foreground
        self.background = background
        self.style      = style
    }

    /// A blank, default-attributed cell.
    public static let blank = ScreenCell()
}
