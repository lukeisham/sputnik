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

    // MARK: - Persistence keys

    private enum DefaultsKey {
        static let theme              = "sputnik.settings.theme"
        static let editorFont         = "sputnik.settings.editorFont"
        static let autoSave           = "sputnik.settings.autoSave"
        static let lineNumbers        = "sputnik.settings.lineNumbers"
        static let wordWrap           = "sputnik.settings.wordWrap"
        static let spellCheck         = "sputnik.settings.spellCheck"
        static let grammarCheck       = "sputnik.settings.grammarCheck"
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
    }
}
