import Foundation

/// Deserialises all `SettingsStore` values from `PersistenceService`.
///
/// Owned by module 2.5 (Persistence) because this is a persistence concern.
/// `SettingsStore` calls this once on init and then uses per-property setters
/// for all subsequent reads/writes (SR-6). Extracted from `SettingsStore.loadFromDefaults()`
/// to separate the deserialisation orchestration from the state model.
struct SettingsLoader {
    private let persistence: any PersistenceService

    init(persistence: any PersistenceService) {
        self.persistence = persistence
    }

    /// Reads every known key from `UserDefaults` and applies the decoded
    /// values to `store`. Falls back to defaults when a key is absent or corrupt.
    @MainActor
    func load(into store: SettingsStore) {
        if let raw: String = persistence.loadSetting(forKey: DefaultsKey.theme),
            let saved = AppTheme(rawValue: raw)
        {
            store.theme = saved
        }
        if let saved: EditorFont = persistence.loadSetting(forKey: DefaultsKey.editorFont) {
            store.editorFont = saved
        }
        if let saved: Bool = persistence.loadSetting(forKey: DefaultsKey.autoSave) {
            store.autoSaveEnabled = saved
        }
        if let saved: Bool = persistence.loadSetting(forKey: DefaultsKey.lineNumbers) {
            store.lineNumbersEnabled = saved
        }
        if let saved: Bool = persistence.loadSetting(forKey: DefaultsKey.wordWrap) {
            store.wordWrapEnabled = saved
        }
        // Load the writing-assist matrix, migrating legacy boolean keys on first run.
        if let saved: WritingAssistMatrix = persistence.loadSetting(
            forKey: DefaultsKey.writingAssist)
        {
            store.writingAssist = saved
        } else {
            var m = WritingAssistMatrix.default
            if let legacySpell: Bool = persistence.loadSetting(forKey: DefaultsKey.spellCheck) {
                m = m.setting(.instantCorrect, for: .spelling, to: legacySpell)
            }
            if let legacyGrammar: Bool = persistence.loadSetting(forKey: DefaultsKey.grammarCheck) {
                m = m.setting(.instantCorrect, for: .grammar, to: legacyGrammar)
            }
            store.writingAssist = m
            persistence.saveSetting(m, forKey: DefaultsKey.writingAssist)
        }
        // Terminal
        if let saved: String = persistence.loadSetting(forKey: DefaultsKey.terminalFontName) {
            store.terminalFontName = saved
        }
        if let saved: Double = persistence.loadSetting(forKey: DefaultsKey.terminalFontSize) {
            store.terminalFontSize = saved
        }
        if let saved: Int = persistence.loadSetting(forKey: DefaultsKey.terminalScrollbackLimit) {
            store.terminalScrollbackLimit = saved
        }
        if let saved: TerminalColor = persistence.loadSetting(
            forKey: DefaultsKey.terminalForeground)
        {
            store.terminalForeground = saved
        }
        if let saved: TerminalColor = persistence.loadSetting(
            forKey: DefaultsKey.terminalBackground)
        {
            store.terminalBackground = saved
        }
        // Editor
        if let saved: Int = persistence.loadSetting(forKey: DefaultsKey.editorMaxFileSizeBytes) {
            store.editorMaxFileSizeBytes = saved
        }
        if let saved: Double = persistence.loadSetting(forKey: DefaultsKey.markdownDebounceInterval)
        {
            store.markdownDebounceInterval = saved
        }
        if let saved: Double = persistence.loadSetting(forKey: DefaultsKey.asciiDebounceInterval) {
            store.asciiDebounceInterval = saved
        }
        if let saved: Double = persistence.loadSetting(forKey: DefaultsKey.htmlDebounceInterval) {
            store.htmlDebounceInterval = saved
        }
        if let saved: Double = persistence.loadSetting(
            forKey: DefaultsKey.spellCheckDebounceInterval)
        {
            store.spellCheckDebounceInterval = saved
        }
        // Auto-complete debounce steps
        if let saved: AutoCompleteDebounceStep = persistence.loadSetting(
            forKey: DefaultsKey.markdownAutoCompleteStep)
        {
            store.markdownAutoCompleteStep = saved
        }
        if let saved: AutoCompleteDebounceStep = persistence.loadSetting(
            forKey: DefaultsKey.asciiAutoCompleteStep)
        {
            store.asciiAutoCompleteStep = saved
        }
        if let saved: AutoCompleteDebounceStep = persistence.loadSetting(
            forKey: DefaultsKey.htmlAutoCompleteStep)
        {
            store.htmlAutoCompleteStep = saved
        }
        if let saved: AutoCompleteDebounceStep = persistence.loadSetting(
            forKey: DefaultsKey.spellingAutoCompleteStep)
        {
            store.spellingAutoCompleteStep = saved
        }
        if let saved: String = persistence.loadSetting(forKey: DefaultsKey.asciiTriggerKey) {
            store.asciiTriggerKey = saved
        }
        if let saved: String? = persistence.loadSetting(forKey: DefaultsKey.spellCheckLocale) {
            store.spellCheckLocale = saved
        }
        // Per-panel fonts
        if let saved: EditorFont = persistence.loadSetting(forKey: DefaultsKey.textEditorFont) {
            store.textEditorFont = saved
        }
        if let saved: EditorFont = persistence.loadSetting(forKey: DefaultsKey.markdownPreviewFont)
        {
            store.markdownPreviewFont = saved
        }
        if let saved: EditorFont = persistence.loadSetting(forKey: DefaultsKey.htmlPreviewFont) {
            store.htmlPreviewFont = saved
        }
        // AI
        if let saved: SupportingAIConfiguration = persistence.loadSetting(
            forKey: DefaultsKey.supportingAIConfig)
        {
            store.supportingAIConfig = saved
        }
        // Migrate from legacy aiConfig key
        if let legacy: SupportingAIConfiguration = persistence.loadSetting(
            forKey: "sputnik.settings.aiConfig")
        {
            store.supportingAIConfig = legacy
            persistence.saveSetting(legacy, forKey: DefaultsKey.supportingAIConfig)
        }
    }
}

// MARK: - Persistence keys (mirrors SettingsStore.DefaultsKey)

private enum DefaultsKey {
    static let theme = "sputnik.settings.theme"
    static let editorFont = "sputnik.settings.editorFont"
    static let autoSave = "sputnik.settings.autoSave"
    static let lineNumbers = "sputnik.settings.lineNumbers"
    static let wordWrap = "sputnik.settings.wordWrap"
    static let spellCheck = "sputnik.settings.spellCheck"
    static let grammarCheck = "sputnik.settings.grammarCheck"
    static let writingAssist = "sputnik.settings.writingAssist"
    static let textEditorFont = "sputnik.settings.textEditorFont"
    static let markdownPreviewFont = "sputnik.settings.markdownPreviewFont"
    static let htmlPreviewFont = "sputnik.settings.htmlPreviewFont"
    static let terminalFontName = "sputnik.settings.terminalFontName"
    static let terminalFontSize = "sputnik.settings.terminalFontSize"
    static let terminalScrollbackLimit = "sputnik.settings.terminalScrollbackLimit"
    static let terminalForeground = "sputnik.settings.terminalForeground"
    static let terminalBackground = "sputnik.settings.terminalBackground"
    static let editorMaxFileSizeBytes = "sputnik.settings.editorMaxFileSizeBytes"
    static let markdownDebounceInterval = "sputnik.settings.markdownDebounceInterval"
    static let asciiDebounceInterval = "sputnik.settings.asciiDebounceInterval"
    static let htmlDebounceInterval = "sputnik.settings.htmlDebounceInterval"
    static let spellCheckDebounceInterval = "sputnik.settings.spellCheckDebounceInterval"
    static let markdownAutoCompleteStep = "sputnik.settings.markdownAutoCompleteStep"
    static let asciiAutoCompleteStep = "sputnik.settings.asciiAutoCompleteStep"
    static let htmlAutoCompleteStep = "sputnik.settings.htmlAutoCompleteStep"
    static let spellingAutoCompleteStep = "sputnik.settings.spellingAutoCompleteStep"
    static let asciiTriggerKey = "sputnik.settings.asciiTriggerKey"
    static let spellCheckLocale = "sputnik.settings.spellCheckLocale"
    static let supportingAIConfig = "sputnik.settings.supportingAIConfig"
}
