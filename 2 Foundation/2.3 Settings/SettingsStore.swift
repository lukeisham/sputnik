import Foundation
import Observation

/// The single source of truth for all user-configurable preferences.
///
/// Created once in `SputnikApp` alongside `AppState` and injected into the view
/// hierarchy via `.environment(settingsStore)`. All modules read from it; they do
/// not access `UserDefaults` or `PersistenceService` directly.
@Observable
@MainActor
public final class SettingsStore {

    // MARK: - Stored properties (trigger @Observable change notifications)

    /// The colour-scheme override. Default: `.system`.
    public var theme: AppTheme = .system

    /// The font used in all text editor panels. Default: SF Mono 13pt.
    public var editorFont: EditorFont = EditorFont()

    /// Whether the editor auto-saves after every significant edit. Default: `true`.
    public var autoSaveEnabled: Bool = true

    /// Whether line numbers are shown in the gutter. Default: `true`.
    public var lineNumbersEnabled: Bool = true

    /// Whether long lines are soft-wrapped. Default: `true`.
    public var wordWrapEnabled: Bool = true

    /// Whether real-time spell checking is active. Default: `true`.
    public var spellCheckEnabled: Bool = true

    /// Whether real-time grammar checking is active (requires `spellCheckEnabled`). Default: `false`.
    public var grammarCheckEnabled: Bool = false

    // MARK: - Terminal settings

    /// Monospace font name used in the terminal panel. Default: `"Menlo"`.
    public var terminalFontName: String = "Menlo"

    /// Font size (points) used in the terminal panel. Default: `13.0`.
    public var terminalFontSize: Double = 13.0

    /// Maximum lines retained in the terminal scrollback buffer. Default: `5_000`.
    public var terminalScrollbackLimit: Int = 5_000

    /// Default foreground colour for terminal text. Default: near-white.
    public var terminalForeground: TerminalColor = TerminalColor(red: 0.88, green: 0.88, blue: 0.88)

    /// Default background colour for the terminal panel. Default: near-black.
    public var terminalBackground: TerminalColor = TerminalColor(red: 0.08, green: 0.08, blue: 0.09)

    // MARK: - Editor settings

    /// Maximum file size (bytes) the editor will open. Default: 10 MB.
    public var editorMaxFileSizeBytes: Int = 10 * 1024 * 1024

    /// Debounce interval (seconds) for Markdown ghost-text suggestions. Default: `0.3`.
    public var markdownDebounceInterval: TimeInterval = 0.3

    /// Debounce interval (seconds) for ASCII art ghost-text suggestions. Default: `0.3`.
    public var asciiDebounceInterval: TimeInterval = 0.3

    /// Debounce interval (seconds) for HTML ghost-text suggestions. Default: `0.3`.
    public var htmlDebounceInterval: TimeInterval = 0.3

    /// Debounce interval (seconds) for spell/grammar checking. Default: `0.5`.
    public var spellCheckDebounceInterval: TimeInterval = 0.5

    /// Trigger key character for ASCII art block completion. Default: `"_"`.
    public var asciiTriggerKey: String = "_"

    /// BCP-47 language tag passed to `NSSpellChecker`. `nil` → system default locale.
    public var spellCheckLocale: String? = nil

    // MARK: - Persistence keys

    private enum DefaultsKey {
        static let theme              = "sputnik.settings.theme"
        static let editorFont         = "sputnik.settings.editorFont"
        static let autoSave           = "sputnik.settings.autoSave"
        static let lineNumbers        = "sputnik.settings.lineNumbers"
        static let wordWrap           = "sputnik.settings.wordWrap"
        static let spellCheck         = "sputnik.settings.spellCheck"
        static let grammarCheck       = "sputnik.settings.grammarCheck"
        // Terminal
        static let terminalFontName        = "sputnik.settings.terminalFontName"
        static let terminalFontSize        = "sputnik.settings.terminalFontSize"
        static let terminalScrollbackLimit = "sputnik.settings.terminalScrollbackLimit"
        static let terminalForeground      = "sputnik.settings.terminalForeground"
        static let terminalBackground      = "sputnik.settings.terminalBackground"
        // Editor
        static let editorMaxFileSizeBytes      = "sputnik.settings.editorMaxFileSizeBytes"
        static let markdownDebounceInterval    = "sputnik.settings.markdownDebounceInterval"
        static let asciiDebounceInterval       = "sputnik.settings.asciiDebounceInterval"
        static let htmlDebounceInterval        = "sputnik.settings.htmlDebounceInterval"
        static let spellCheckDebounceInterval  = "sputnik.settings.spellCheckDebounceInterval"
        static let asciiTriggerKey             = "sputnik.settings.asciiTriggerKey"
        static let spellCheckLocale            = "sputnik.settings.spellCheckLocale"
    }

    // MARK: - Dependencies

    private let persistence: any PersistenceService

    // MARK: - Init

    public init(persistence: any PersistenceService) {
        self.persistence = persistence
        loadFromDefaults()
    }

    // MARK: - Public mutators (each persists asynchronously via PersistenceService)

    public func setTheme(_ value: AppTheme) {
        theme = value
        persistence.saveSetting(value.rawValue, forKey: DefaultsKey.theme)
    }

    public func setEditorFont(_ value: EditorFont) {
        editorFont = value
        persistence.saveSetting(value, forKey: DefaultsKey.editorFont)
    }

    public func setAutoSaveEnabled(_ value: Bool) {
        autoSaveEnabled = value
        persistence.saveSetting(value, forKey: DefaultsKey.autoSave)
    }

    public func setLineNumbersEnabled(_ value: Bool) {
        lineNumbersEnabled = value
        persistence.saveSetting(value, forKey: DefaultsKey.lineNumbers)
    }

    public func setWordWrapEnabled(_ value: Bool) {
        wordWrapEnabled = value
        persistence.saveSetting(value, forKey: DefaultsKey.wordWrap)
    }

    public func setSpellCheckEnabled(_ value: Bool) {
        spellCheckEnabled = value
        persistence.saveSetting(value, forKey: DefaultsKey.spellCheck)
    }

    public func setGrammarCheckEnabled(_ value: Bool) {
        grammarCheckEnabled = value
        persistence.saveSetting(value, forKey: DefaultsKey.grammarCheck)
    }

    // MARK: - Terminal mutators

    public func setTerminalFontName(_ value: String) {
        terminalFontName = value
        persistence.saveSetting(value, forKey: DefaultsKey.terminalFontName)
    }

    public func setTerminalFontSize(_ value: Double) {
        terminalFontSize = value
        persistence.saveSetting(value, forKey: DefaultsKey.terminalFontSize)
    }

    public func setTerminalScrollbackLimit(_ value: Int) {
        terminalScrollbackLimit = value
        persistence.saveSetting(value, forKey: DefaultsKey.terminalScrollbackLimit)
    }

    public func setTerminalForeground(_ value: TerminalColor) {
        terminalForeground = value
        persistence.saveSetting(value, forKey: DefaultsKey.terminalForeground)
    }

    public func setTerminalBackground(_ value: TerminalColor) {
        terminalBackground = value
        persistence.saveSetting(value, forKey: DefaultsKey.terminalBackground)
    }

    // MARK: - Editor mutators

    public func setEditorMaxFileSizeBytes(_ value: Int) {
        editorMaxFileSizeBytes = value
        persistence.saveSetting(value, forKey: DefaultsKey.editorMaxFileSizeBytes)
    }

    public func setMarkdownDebounceInterval(_ value: TimeInterval) {
        markdownDebounceInterval = value
        persistence.saveSetting(value, forKey: DefaultsKey.markdownDebounceInterval)
    }

    public func setAsciiDebounceInterval(_ value: TimeInterval) {
        asciiDebounceInterval = value
        persistence.saveSetting(value, forKey: DefaultsKey.asciiDebounceInterval)
    }

    public func setHtmlDebounceInterval(_ value: TimeInterval) {
        htmlDebounceInterval = value
        persistence.saveSetting(value, forKey: DefaultsKey.htmlDebounceInterval)
    }

    public func setSpellCheckDebounceInterval(_ value: TimeInterval) {
        spellCheckDebounceInterval = value
        persistence.saveSetting(value, forKey: DefaultsKey.spellCheckDebounceInterval)
    }

    public func setAsciiTriggerKey(_ value: String) {
        asciiTriggerKey = value
        persistence.saveSetting(value, forKey: DefaultsKey.asciiTriggerKey)
    }

    public func setSpellCheckLocale(_ value: String?) {
        spellCheckLocale = value
        persistence.saveSetting(value, forKey: DefaultsKey.spellCheckLocale)
    }

    // MARK: - Private helpers

    private func loadFromDefaults() {
        if let raw: String = persistence.loadSetting(forKey: DefaultsKey.theme),
           let saved = AppTheme(rawValue: raw) {
            theme = saved
        }
        if let saved: EditorFont = persistence.loadSetting(forKey: DefaultsKey.editorFont) {
            editorFont = saved
        }
        if let saved: Bool = persistence.loadSetting(forKey: DefaultsKey.autoSave) {
            autoSaveEnabled = saved
        }
        if let saved: Bool = persistence.loadSetting(forKey: DefaultsKey.lineNumbers) {
            lineNumbersEnabled = saved
        }
        if let saved: Bool = persistence.loadSetting(forKey: DefaultsKey.wordWrap) {
            wordWrapEnabled = saved
        }
        if let saved: Bool = persistence.loadSetting(forKey: DefaultsKey.spellCheck) {
            spellCheckEnabled = saved
        }
        if let saved: Bool = persistence.loadSetting(forKey: DefaultsKey.grammarCheck) {
            grammarCheckEnabled = saved
        }
        // Terminal
        if let saved: String = persistence.loadSetting(forKey: DefaultsKey.terminalFontName) {
            terminalFontName = saved
        }
        if let saved: Double = persistence.loadSetting(forKey: DefaultsKey.terminalFontSize) {
            terminalFontSize = saved
        }
        if let saved: Int = persistence.loadSetting(forKey: DefaultsKey.terminalScrollbackLimit) {
            terminalScrollbackLimit = saved
        }
        if let saved: TerminalColor = persistence.loadSetting(forKey: DefaultsKey.terminalForeground) {
            terminalForeground = saved
        }
        if let saved: TerminalColor = persistence.loadSetting(forKey: DefaultsKey.terminalBackground) {
            terminalBackground = saved
        }
        // Editor
        if let saved: Int = persistence.loadSetting(forKey: DefaultsKey.editorMaxFileSizeBytes) {
            editorMaxFileSizeBytes = saved
        }
        if let saved: Double = persistence.loadSetting(forKey: DefaultsKey.markdownDebounceInterval) {
            markdownDebounceInterval = saved
        }
        if let saved: Double = persistence.loadSetting(forKey: DefaultsKey.asciiDebounceInterval) {
            asciiDebounceInterval = saved
        }
        if let saved: Double = persistence.loadSetting(forKey: DefaultsKey.htmlDebounceInterval) {
            htmlDebounceInterval = saved
        }
        if let saved: Double = persistence.loadSetting(forKey: DefaultsKey.spellCheckDebounceInterval) {
            spellCheckDebounceInterval = saved
        }
        if let saved: String = persistence.loadSetting(forKey: DefaultsKey.asciiTriggerKey) {
            asciiTriggerKey = saved
        }
        if let saved: String? = persistence.loadSetting(forKey: DefaultsKey.spellCheckLocale) {
            spellCheckLocale = saved
        }
    }
}
