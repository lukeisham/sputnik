import Foundation

// MARK: - Writing Assist Language

/// The language/mode axis of the writing-assist toggle matrix (Foundation 2.3).
public enum WritingAssistLanguage: String, Codable, CaseIterable, Sendable {
    case spelling
    case grammar
    case markdown
    case html
    case json
    case asciiArt
}

// MARK: - Writing Assist Function

/// The function axis of the writing-assist toggle matrix.
public enum WritingAssistFunction: String, Codable, CaseIterable, Sendable {
    case instantCorrect
    case autoComplete
    case moreContext
    case interaction
}

// MARK: - Writing Assist Matrix

/// The per-language × per-function writing-assist toggle matrix (ISS-011).
///
/// Only applicable cells are stored; non-applicable cells always return `false`
/// from `isEnabled(_:for:)` and are never shown in the Writing Assistance menu.
///
/// Applicability:
/// | Language  | Instant Correct | Auto-Complete | More Context | Interaction |
/// |-----------|:---:|:---:|:---:|:---:|
/// | Spelling  |  ✓  |  ✓  |  —  |  —  |
/// | Grammar   |  ✓  |  —  |  ✓  |  ✓  |
/// | Markdown  |  —  |  ✓  |  ✓  |  ✓  |
/// | HTML      |  —  |  ✓  |  ✓  |  ✓  |
/// | JSON      |  —  |  ✓  |  ✓  |  ✓  |
/// | ASCII Art |  —  |  ✓  |  —  |  ✓  |
public struct WritingAssistMatrix: Codable, Sendable, Equatable {

    // MARK: - Storage (keyed by "<fn>.<lang>")

    private var cells: [String: Bool] = [:]

    // MARK: - Default

    /// Default matrix — Auto-Complete and More Context on, Instant Correct off.
    public static let `default`: WritingAssistMatrix = {
        var m = WritingAssistMatrix()
        for lang in WritingAssistLanguage.allCases {
            for fn in WritingAssistFunction.allCases where WritingAssistMatrix.applies(fn, to: lang)
            {
                m.cells[WritingAssistMatrix.cellKey(fn, lang)] = (fn != .instantCorrect)
            }
        }
        return m
    }()

    // MARK: - Applicability

    /// Returns `true` when `fn` × `lang` is a real, actionable cell in the matrix.
    public static func applies(_ fn: WritingAssistFunction, to lang: WritingAssistLanguage) -> Bool
    {
        switch fn {
        case .instantCorrect:
            return lang == .spelling || lang == .grammar
        case .autoComplete:
            return lang == .spelling || lang == .markdown || lang == .html || lang == .json
                || lang == .asciiArt
        case .moreContext:
            return lang == .grammar || lang == .markdown || lang == .html || lang == .json
        case .interaction:
            return lang == .grammar || lang == .markdown || lang == .html || lang == .json
                || lang == .asciiArt
        }
    }

    // MARK: - Read / Write

    /// Returns whether `fn` × `lang` is currently on. Non-applicable cells always return `false`.
    public func isEnabled(_ fn: WritingAssistFunction, for lang: WritingAssistLanguage) -> Bool {
        guard WritingAssistMatrix.applies(fn, to: lang) else { return false }
        // Fallback: AutoComplete/MoreContext default on; InstantCorrect defaults off.
        return cells[WritingAssistMatrix.cellKey(fn, lang)] ?? (fn != .instantCorrect)
    }

    /// Returns a copy of the matrix with the specified cell toggled to `value`.
    /// No-ops silently for non-applicable cells.
    public func setting(
        _ fn: WritingAssistFunction, for lang: WritingAssistLanguage, to value: Bool
    ) -> WritingAssistMatrix {
        guard WritingAssistMatrix.applies(fn, to: lang) else { return self }
        var copy = self
        copy.cells[WritingAssistMatrix.cellKey(fn, lang)] = value
        return copy
    }

    // MARK: - Convenience presets

    /// All applicable cells set to `true`.
    public static func allOn() -> WritingAssistMatrix {
        var m = WritingAssistMatrix()
        for lang in WritingAssistLanguage.allCases {
            for fn in WritingAssistFunction.allCases where applies(fn, to: lang) {
                m.cells[cellKey(fn, lang)] = true
            }
        }
        return m
    }

    /// All applicable cells set to `false`.
    public static func allOff() -> WritingAssistMatrix {
        var m = WritingAssistMatrix()
        for lang in WritingAssistLanguage.allCases {
            for fn in WritingAssistFunction.allCases where applies(fn, to: lang) {
                m.cells[cellKey(fn, lang)] = false
            }
        }
        return m
    }

    // MARK: - Private

    private static func cellKey(_ fn: WritingAssistFunction, _ lang: WritingAssistLanguage)
        -> String
    {
        "\(fn.rawValue).\(lang.rawValue)"
    }
}
