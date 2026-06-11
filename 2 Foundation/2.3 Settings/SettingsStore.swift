import Foundation
import Observation
import SwiftUI

/// The single source of truth for all user-configurable preferences.
///
/// Created once in `SputnikApp` alongside `AppState` and injected into the view
/// hierarchy via `.environment(settingsStore)`. All modules read from it; they do
/// not access `UserDefaults` or `PersistenceService` directly.
@Observable
@MainActor
public final class SettingsStore: @unchecked Sendable {

    // MARK: - Stored properties (trigger @Observable change notifications)

    /// The colour-scheme override. Default: `.system`.
    public var theme: AppTheme = .system

    /// The font used in all text editor panels. Default: SF Mono 13pt.
    public var editorFont: EditorFont = EditorFont()

    // MARK: - Per-panel font overrides (F-4)

    /// Per-panel font override for the Text Editor. `nil` → inherit global `editorFont`.
    public var textEditorFont: EditorFont?

    /// Per-panel font override for the Markdown Preview. `nil` → inherit global `editorFont`.
    public var markdownPreviewFont: EditorFont?

    /// Per-panel font override for the HTML Preview. `nil` → inherit global `editorFont`.
    public var htmlPreviewFont: EditorFont?

    // MARK: - Computed font resolvers (F-4)
    //
    // Each panel reads its own resolved property. When the per-panel override is nil,
    // the global `editorFont` is used as the fallback — panels never read `editorFont`
    // directly (SR-1: single source of truth).

    /// The effective font for the Text Editor: per-panel override or global default.
    public var resolvedTextEditorFont: EditorFont {
        textEditorFont ?? editorFont
    }

    /// The effective font for the Markdown Preview: per-panel override or global default.
    public var resolvedMarkdownPreviewFont: EditorFont {
        markdownPreviewFont ?? editorFont
    }

    /// The effective font for the HTML Preview: per-panel override or global default.
    public var resolvedHtmlPreviewFont: EditorFont {
        htmlPreviewFont ?? editorFont
    }

    // MARK: - Per-panel background colours (F-4)

    /// Background colour for the Text Editor. Default: editor background.
    public var textEditorBackground: Color = SputnikColor.editorBackground

    /// Background colour for the Markdown Preview. Default: window background.
    public var markdownPreviewBackground: Color = SputnikColor.background

    /// Background colour for the HTML Preview. Default: window background.
    public var htmlPreviewBackground: Color = SputnikColor.background

    /// Whether the editor auto-saves after every significant edit. Default: `true`.
    public var autoSaveEnabled: Bool = true

    /// Whether line numbers are shown in the gutter. Default: `true`.
    public var lineNumbersEnabled: Bool = true

    /// Whether long lines are soft-wrapped. Default: `true`.
    public var wordWrapEnabled: Bool = true

    /// The per-language × per-function writing-assist toggle matrix (ISS-011).
    /// `spellCheckEnabled` / `grammarCheckEnabled` are computed over this matrix.
    public var writingAssist: WritingAssistMatrix = .default

    /// Whether Instant Correct is on for Spelling. Computed over `writingAssist` (ISS-011).
    public var spellCheckEnabled: Bool {
        writingAssist.isEnabled(.instantCorrect, for: .spelling)
    }

    /// Whether Instant Correct is on for Grammar. Computed over `writingAssist` (ISS-011).
    public var grammarCheckEnabled: Bool {
        writingAssist.isEnabled(.instantCorrect, for: .grammar)
    }

    /// Supporting AI provider configuration (provider, model name + base URL).
    /// The API key is stored separately in the Keychain — see `KeychainService`.
    /// Default: .deepSeek provider, empty model name, no base URL.
    public var supportingAIConfig: SupportingAIConfiguration = SupportingAIConfiguration()

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

    // MARK: - Auto-complete debounce steps

    /// Stepped debounce for Markdown ghost-text auto-complete. Default: `.half` (0.5 s).
    public var markdownAutoCompleteStep: AutoCompleteDebounceStep = .default

    /// Stepped debounce for ASCII art ghost-text auto-complete. Default: `.half` (0.5 s).
    public var asciiAutoCompleteStep: AutoCompleteDebounceStep = .default

    /// Stepped debounce for HTML ghost-text auto-complete. Default: `.half` (0.5 s).
    public var htmlAutoCompleteStep: AutoCompleteDebounceStep = .default

    /// Stepped debounce for spelling ghost-text auto-complete. Default: `.half` (0.5 s).
    public var spellingAutoCompleteStep: AutoCompleteDebounceStep = .default

    /// Trigger key character for ASCII art block completion. Default: `"_"`.
    public var asciiTriggerKey: String = "_"

    /// BCP-47 language tag passed to `NSSpellChecker`. `nil` → system default locale.
    public var spellCheckLocale: String? = nil

    // MARK: - Persistence keys

    private enum DefaultsKey {
        static let theme = "sputnik.settings.theme"
        static let editorFont = "sputnik.settings.editorFont"
        static let autoSave = "sputnik.settings.autoSave"
        static let lineNumbers = "sputnik.settings.lineNumbers"
        static let wordWrap = "sputnik.settings.wordWrap"
        // Legacy keys kept for migration only; new code reads/writes writingAssist.
        static let spellCheck = "sputnik.settings.spellCheck"
        static let grammarCheck = "sputnik.settings.grammarCheck"
        static let writingAssist = "sputnik.settings.writingAssist"
        // Per-panel fonts
        static let textEditorFont = "sputnik.settings.textEditorFont"
        static let markdownPreviewFont = "sputnik.settings.markdownPreviewFont"
        static let htmlPreviewFont = "sputnik.settings.htmlPreviewFont"
        // Terminal
        static let terminalFontName = "sputnik.settings.terminalFontName"
        static let terminalFontSize = "sputnik.settings.terminalFontSize"
        static let terminalScrollbackLimit = "sputnik.settings.terminalScrollbackLimit"
        static let terminalForeground = "sputnik.settings.terminalForeground"
        static let terminalBackground = "sputnik.settings.terminalBackground"
        // Editor
        static let editorMaxFileSizeBytes = "sputnik.settings.editorMaxFileSizeBytes"
        static let markdownDebounceInterval = "sputnik.settings.markdownDebounceInterval"
        static let asciiDebounceInterval = "sputnik.settings.asciiDebounceInterval"
        static let htmlDebounceInterval = "sputnik.settings.htmlDebounceInterval"
        static let spellCheckDebounceInterval = "sputnik.settings.spellCheckDebounceInterval"
        // Auto-complete debounce steps
        static let markdownAutoCompleteStep = "sputnik.settings.markdownAutoCompleteStep"
        static let asciiAutoCompleteStep = "sputnik.settings.asciiAutoCompleteStep"
        static let htmlAutoCompleteStep = "sputnik.settings.htmlAutoCompleteStep"
        static let spellingAutoCompleteStep = "sputnik.settings.spellingAutoCompleteStep"
        static let asciiTriggerKey = "sputnik.settings.asciiTriggerKey"
        static let spellCheckLocale = "sputnik.settings.spellCheckLocale"
        // AI
        static let supportingAIConfig = "sputnik.settings.supportingAIConfig"
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

    /// Replaces the entire writing-assist matrix and persists it.
    public func setWritingAssistMatrix(_ matrix: WritingAssistMatrix) {
        writingAssist = matrix
        persistence.saveSetting(matrix, forKey: DefaultsKey.writingAssist)
    }

    /// Writes a single cell in the writing-assist matrix and persists the result.
    public func setWritingAssist(
        _ fn: WritingAssistFunction, for lang: WritingAssistLanguage, to value: Bool
    ) {
        writingAssist = writingAssist.setting(fn, for: lang, to: value)
        persistence.saveSetting(writingAssist, forKey: DefaultsKey.writingAssist)
    }

    /// Convenience wrapper retained for existing consumers — updates `spelling × instantCorrect`.
    public func setSpellCheckEnabled(_ value: Bool) {
        setWritingAssist(.instantCorrect, for: .spelling, to: value)
    }

    /// Convenience wrapper retained for existing consumers — updates `grammar × instantCorrect`.
    public func setGrammarCheckEnabled(_ value: Bool) {
        setWritingAssist(.instantCorrect, for: .grammar, to: value)
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

    // MARK: - Auto-complete step mutators

    public func setMarkdownAutoCompleteStep(_ value: AutoCompleteDebounceStep) {
        markdownAutoCompleteStep = value
        persistence.saveSetting(value, forKey: DefaultsKey.markdownAutoCompleteStep)
    }

    public func setAsciiAutoCompleteStep(_ value: AutoCompleteDebounceStep) {
        asciiAutoCompleteStep = value
        persistence.saveSetting(value, forKey: DefaultsKey.asciiAutoCompleteStep)
    }

    public func setHtmlAutoCompleteStep(_ value: AutoCompleteDebounceStep) {
        htmlAutoCompleteStep = value
        persistence.saveSetting(value, forKey: DefaultsKey.htmlAutoCompleteStep)
    }

    public func setSpellingAutoCompleteStep(_ value: AutoCompleteDebounceStep) {
        spellingAutoCompleteStep = value
        persistence.saveSetting(value, forKey: DefaultsKey.spellingAutoCompleteStep)
    }

    public func setAsciiTriggerKey(_ value: String) {
        asciiTriggerKey = value
        persistence.saveSetting(value, forKey: DefaultsKey.asciiTriggerKey)
    }

    // MARK: - Per-panel font mutators (F-4)

    public func setTextEditorFont(_ value: EditorFont?) {
        textEditorFont = value
        persistence.saveSetting(value, forKey: DefaultsKey.textEditorFont)
    }

    public func setMarkdownPreviewFont(_ value: EditorFont?) {
        markdownPreviewFont = value
        persistence.saveSetting(value, forKey: DefaultsKey.markdownPreviewFont)
    }

    public func setHtmlPreviewFont(_ value: EditorFont?) {
        htmlPreviewFont = value
        persistence.saveSetting(value, forKey: DefaultsKey.htmlPreviewFont)
    }

    // MARK: - Per-panel background colour mutators (F-4)
    //
    // SputnikColor is a computed enum (not Codable), so background colours are kept in
    // memory only. Persistence is a future enhancement.

    public func setTextEditorBackground(_ value: Color) {
        textEditorBackground = value
    }

    public func setMarkdownPreviewBackground(_ value: Color) {
        markdownPreviewBackground = value
    }

    public func setHtmlPreviewBackground(_ value: Color) {
        htmlPreviewBackground = value
    }

    // MARK: - AI mutators

    public func setSupportingAIConfig(_ config: SupportingAIConfiguration) {
        supportingAIConfig = config
        persistence.saveSetting(config, forKey: DefaultsKey.supportingAIConfig)
    }

    public func setSpellCheckLocale(_ value: String?) {
        spellCheckLocale = value
        persistence.saveSetting(value, forKey: DefaultsKey.spellCheckLocale)
    }

    // MARK: - Private helpers

    private func loadFromDefaults() {
        let loader = SettingsLoader(persistence: persistence)
        loader.load(into: self)
    }
}
