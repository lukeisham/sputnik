import Foundation

/// Modifier keys active during a terminal key event.
///
/// Represented independently of `NSEvent.ModifierFlags` so `KeyEncoder` remains
/// AppKit-free and trivially testable (SR-6, plan spec 7.6).
public struct TerminalModifiers: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let control = TerminalModifiers(rawValue: 1 << 0)
    public static let shift   = TerminalModifiers(rawValue: 1 << 1)
    public static let option  = TerminalModifiers(rawValue: 1 << 2)
    public static let command = TerminalModifiers(rawValue: 1 << 3)
}

/// A platform-independent representation of a key event.
///
/// `TerminalTextView` (AppKit) builds one of these from `NSEvent` and passes it
/// to `KeyEncoder.encode(_:)`. `KeyEncoder` itself never imports AppKit.
public struct TerminalKeyEvent: Sendable {
    /// macOS virtual key code.
    public let keyCode: UInt16
    /// Characters produced by the key (before modifier remapping).
    public let characters: String
    /// Active modifier flags at the time of the event.
    public let modifiers: TerminalModifiers

    public init(keyCode: UInt16, characters: String, modifiers: TerminalModifiers) {
        self.keyCode    = keyCode
        self.characters = characters
        self.modifiers  = modifiers
    }
}

/// Translates macOS key events into the ANSI/VT byte sequences that Zsh expects.
///
/// Pure and AppKit-free: input is a `TerminalKeyEvent` (Foundation-only struct);
/// output is `Data` containing raw bytes. Trivially testable in isolation (SR-6, spec 7.6).
public enum KeyEncoder {

    // MARK: - Entry point

    /// Returns the ANSI byte sequence for the given key event, or `nil` if the
    /// event should not be forwarded to the shell (e.g. modifier-only or Command presses).
    public static func encode(_ event: TerminalKeyEvent) -> Data? {
        let chars = event.characters
        let mods  = event.modifiers

        // Ctrl+key shortcuts
        if mods.contains(.control), let byte = ctrlByte(for: chars) {
            return Data([byte])
        }

        // Named special keys
        if let sequence = specialKeySequence(for: event.keyCode, modifiers: mods) {
            return sequence
        }

        // Printable characters — suppress Command-combos
        guard !chars.isEmpty, !mods.contains(.command) else { return nil }
        return chars.data(using: .utf8)
    }

    // MARK: - Ctrl mapping

    private static func ctrlByte(for chars: String) -> UInt8? {
        guard let first = chars.unicodeScalars.first else { return nil }
        let value = first.value
        if (0x61...0x7A).contains(value) { return UInt8(value - 0x60) }
        if (0x41...0x5A).contains(value) { return UInt8(value - 0x40) }
        switch value {
        case 0x40: return 0x00
        case 0x5B: return 0x1B
        case 0x5C: return 0x1C
        case 0x5D: return 0x1D
        case 0x5E: return 0x1E
        case 0x5F: return 0x1F
        default:   return nil
        }
    }

    // MARK: - Special keys (macOS virtual key codes)

    private enum KC {
        static let returnKey:  UInt16 = 36
        static let tab:        UInt16 = 48
        static let delete:     UInt16 = 51
        static let escape:     UInt16 = 53
        static let forwardDel: UInt16 = 117
        static let home:       UInt16 = 115
        static let end:        UInt16 = 119
        static let pageUp:     UInt16 = 116
        static let pageDown:   UInt16 = 121
        static let leftArrow:  UInt16 = 123
        static let rightArrow: UInt16 = 124
        static let downArrow:  UInt16 = 125
        static let upArrow:    UInt16 = 126
    }

    private static func specialKeySequence(
        for keyCode: UInt16,
        modifiers: TerminalModifiers
    ) -> Data? {
        let shifted  = modifiers.contains(.shift)
        let optioned = modifiers.contains(.option)

        switch keyCode {
        case KC.returnKey:   return data(0x0D)
        case KC.tab:         return shifted ? esc("[Z") : data(0x09)
        case KC.delete:      return data(0x7F)
        case KC.escape:      return data(0x1B)
        case KC.forwardDel:  return esc("[3~")
        case KC.home:        return optioned ? esc("[1~") : esc("[H")
        case KC.end:         return optioned ? esc("[4~") : esc("[F")
        case KC.pageUp:      return esc("[5~")
        case KC.pageDown:    return esc("[6~")
        case KC.upArrow:     return shifted ? esc("[1;2A") : esc("[A")
        case KC.downArrow:   return shifted ? esc("[1;2B") : esc("[B")
        case KC.rightArrow:  return shifted ? esc("[1;2C") : esc("[C")
        case KC.leftArrow:   return shifted ? esc("[1;2D") : esc("[D")
        default:             return nil
        }
    }

    // MARK: - Helpers

    private static func data(_ byte: UInt8) -> Data { Data([byte]) }

    private static func esc(_ suffix: String) -> Data {
        var result = Data([0x1B])
        result.append(contentsOf: suffix.utf8)
        return result
    }
}
