// JSONLanguageTests.swift
// Tests for Module 3.6 JSON Language — JSONValidator, JSONLanguageProvider (unit-testable
// surface), SyntaxHighlighter.jsonAttributes, and EditorViewModel.modeForFileType.

import AppKit
import Foundation
import FoundationModule
import Testing

@testable import TextEditorModule

// MARK: - JSONValidatorTests

@MainActor
struct JSONValidatorTests {

    private func makeValidator() -> JSONValidator {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        vm.jsonModeActive = true
        let settings = SettingsStore()
        settings.setJsonValidationEnabled(true)
        return JSONValidator(viewModel: vm, settings: settings)
    }

    // MARK: Happy path

    @Test func validObjectClearsErrors() async throws {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        vm.jsonModeActive = true
        let settings = SettingsStore()
        settings.setJsonValidationEnabled(true)
        let validator = JSONValidator(viewModel: vm, settings: settings)
        validator.validate(text: #"{"key": "value"}"#)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(vm.jsonValidationErrors.isEmpty)
    }

    @Test func validArrayClearsErrors() async throws {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        vm.jsonModeActive = true
        let settings = SettingsStore()
        settings.setJsonValidationEnabled(true)
        let validator = JSONValidator(viewModel: vm, settings: settings)
        validator.validate(text: "[1, 2, 3]")
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(vm.jsonValidationErrors.isEmpty)
    }

    @Test func validFragmentClearsErrors() async throws {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        vm.jsonModeActive = true
        let settings = SettingsStore()
        settings.setJsonValidationEnabled(true)
        let validator = JSONValidator(viewModel: vm, settings: settings)
        validator.validate(text: "true")
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(vm.jsonValidationErrors.isEmpty)
    }

    @Test func validNullFragment() async throws {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        vm.jsonModeActive = true
        let settings = SettingsStore()
        settings.setJsonValidationEnabled(true)
        let validator = JSONValidator(viewModel: vm, settings: settings)
        validator.validate(text: "null")
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(vm.jsonValidationErrors.isEmpty)
    }

    // MARK: Invalid JSON

    @Test func trailingCommaProducesError() async throws {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        vm.jsonModeActive = true
        let settings = SettingsStore()
        settings.setJsonValidationEnabled(true)
        let validator = JSONValidator(viewModel: vm, settings: settings)
        validator.validate(text: #"{"a": 1,}"#)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(!vm.jsonValidationErrors.isEmpty)
    }

    @Test func unclosedObjectProducesError() async throws {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        vm.jsonModeActive = true
        let settings = SettingsStore()
        settings.setJsonValidationEnabled(true)
        let validator = JSONValidator(viewModel: vm, settings: settings)
        validator.validate(text: #"{"a": 1"#)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(!vm.jsonValidationErrors.isEmpty)
    }

    @Test func singleQuoteStringProducesError() async throws {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        vm.jsonModeActive = true
        let settings = SettingsStore()
        settings.setJsonValidationEnabled(true)
        let validator = JSONValidator(viewModel: vm, settings: settings)
        validator.validate(text: "{'key': 'value'}")
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(!vm.jsonValidationErrors.isEmpty)
    }

    // MARK: Edge cases

    @Test func emptyStringClearsErrors() async throws {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        vm.jsonModeActive = true
        let settings = SettingsStore()
        settings.setJsonValidationEnabled(true)
        let validator = JSONValidator(viewModel: vm, settings: settings)
        vm.jsonValidationErrors = [JSONValidator.JSONError(message: "old", characterOffset: nil)]
        validator.validate(text: "")
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(vm.jsonValidationErrors.isEmpty)
    }

    @Test func whitespaceOnlyStringClearsErrors() async throws {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        vm.jsonModeActive = true
        let settings = SettingsStore()
        settings.setJsonValidationEnabled(true)
        let validator = JSONValidator(viewModel: vm, settings: settings)
        validator.validate(text: "   \n  \t  ")
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(vm.jsonValidationErrors.isEmpty)
    }

    @Test func disabledValidationClearsErrors() async throws {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        vm.jsonModeActive = true
        let settings = SettingsStore()
        settings.setJsonValidationEnabled(false)
        let validator = JSONValidator(viewModel: vm, settings: settings)
        vm.jsonValidationErrors = [JSONValidator.JSONError(message: "stale", characterOffset: nil)]
        validator.validate(text: "{bad}")
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(vm.jsonValidationErrors.isEmpty)
    }

    @Test func inactiveModeSkipsValidation() async throws {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        vm.jsonModeActive = false
        let settings = SettingsStore()
        settings.setJsonValidationEnabled(true)
        let validator = JSONValidator(viewModel: vm, settings: settings)
        vm.jsonValidationErrors = [JSONValidator.JSONError(message: "stale", characterOffset: nil)]
        validator.validate(text: "{bad}")
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(vm.jsonValidationErrors.isEmpty)
    }

    @Test func errorContainsNonEmptyMessage() async throws {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        vm.jsonModeActive = true
        let settings = SettingsStore()
        settings.setJsonValidationEnabled(true)
        let validator = JSONValidator(viewModel: vm, settings: settings)
        validator.validate(text: "{bad json}")
        try await Task.sleep(nanoseconds: 200_000_000)
        if let err = vm.jsonValidationErrors.first {
            #expect(!err.message.isEmpty)
        }
    }
}

// MARK: - JSONLanguageSuggestionTests

struct JSONLanguageSuggestionTests {

    @Test func openBraceSuggestsKeyTemplate() {
        let result = invokeSuggest(in: "{")
        #expect(result == "\"key\": ")
    }

    @Test func colonSuggestsEmptyString() {
        let result = invokeSuggest(in: "  \"name\":")
        #expect(result == " \"\"")
    }

    @Test func commaSuggestsSpace() {
        let result = invokeSuggest(in: "[1, 2,")
        #expect(result == " ")
    }

    @Test func openBracketSuggestsEmptyString() {
        let result = invokeSuggest(in: "[")
        #expect(result == "\"\"")
    }

    @Test func emptyTextReturnsNil() {
        let result = invokeSuggest(in: "")
        #expect(result == nil)
    }

    @Test func whitespaceOnlyReturnsNil() {
        let result = invokeSuggest(in: "  \n  ")
        #expect(result == nil)
    }

    @Test func closingBraceReturnsNil() {
        let result = invokeSuggest(in: "{\"a\": 1}")
        #expect(result == nil)
    }

    @Test func numberLastReturnsNil() {
        let result = invokeSuggest(in: "{\"a\": 42")
        #expect(result == nil)
    }

    private func invokeSuggest(in text: String) -> String? {
        JSONLanguageProvider.suggest(in: text)
    }
}

// MARK: - SyntaxHighlighterJSONTests

struct SyntaxHighlighterJSONTests {

    private func makeHighlighter() -> SyntaxHighlighter {
        let storage = NSTextStorage()
        return SyntaxHighlighter(textStorage: storage)
    }

    @Test func keyReceivesBlueColor() {
        let h = makeHighlighter()
        let attrs = h.jsonAttributes(in: #"{"name": "Ada"}"#)
        let keyAttrs = attrs.filter { $0.1 == .systemBlue }
        #expect(!keyAttrs.isEmpty)
    }

    @Test func stringValueReceivesGreenColor() {
        let h = makeHighlighter()
        let attrs = h.jsonAttributes(in: #"{"name": "Ada"}"#)
        let green = attrs.filter { $0.1 == .systemGreen }
        #expect(!green.isEmpty)
    }

    @Test func numberReceivesOrangeColor() {
        let h = makeHighlighter()
        let attrs = h.jsonAttributes(in: #"{"count": 42}"#)
        let orange = attrs.filter { $0.1 == .systemOrange }
        #expect(!orange.isEmpty)
    }

    @Test func trueKeywordReceivesPurpleColor() {
        let h = makeHighlighter()
        let attrs = h.jsonAttributes(in: #"{"flag": true}"#)
        let purple = attrs.filter { $0.1 == .systemPurple }
        #expect(!purple.isEmpty)
    }

    @Test func falseKeywordReceivesPurpleColor() {
        let h = makeHighlighter()
        let attrs = h.jsonAttributes(in: #"{"flag": false}"#)
        let purple = attrs.filter { $0.1 == .systemPurple }
        #expect(!purple.isEmpty)
    }

    @Test func nullKeywordReceivesPurpleColor() {
        let h = makeHighlighter()
        let attrs = h.jsonAttributes(in: #"{"val": null}"#)
        let purple = attrs.filter { $0.1 == .systemPurple }
        #expect(!purple.isEmpty)
    }

    @Test func emptyObjectProducesNoAttributes() {
        let h = makeHighlighter()
        let attrs = h.jsonAttributes(in: "{}")
        #expect(attrs.isEmpty)
    }

    @Test func negativeNumberReceivesOrangeColor() {
        let h = makeHighlighter()
        let attrs = h.jsonAttributes(in: #"{"temp": -7}"#)
        let orange = attrs.filter { $0.1 == .systemOrange }
        #expect(!orange.isEmpty)
    }

    @Test func floatReceivesOrangeColor() {
        let h = makeHighlighter()
        let attrs = h.jsonAttributes(in: #"{"pi": 3.14}"#)
        let orange = attrs.filter { $0.1 == .systemOrange }
        #expect(!orange.isEmpty)
    }

    @Test func noSpuriousColorsInPlainText() {
        let h = makeHighlighter()
        let attrs = h.jsonAttributes(in: "hello world")
        #expect(attrs.isEmpty)
    }
}

// MARK: - EditorViewModelModeForFileTypeTests

@MainActor
struct EditorViewModelModeForFileTypeTests {

    @Test func jsonFileTypeMapsTojsonMode() {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        #expect(vm.modeForFileType(.json) == .json)
    }

    @Test func htmlFileTypeMapsToHtmlMode() {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        #expect(vm.modeForFileType(.html) == .html)
    }

    @Test func markdownFileTypeMapsToMarkdownMode() {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        #expect(vm.modeForFileType(.markdown) == .markdown)
    }

    @Test func textFileTypeMapsToPlainText() {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        #expect(vm.modeForFileType(.text) == .plainText)
    }

    @Test func pdfFileTypeMapsToPlainText() {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        #expect(vm.modeForFileType(.pdf) == .plainText)
    }

    @Test func unknownFileTypeMapsToPlainText() {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        #expect(vm.modeForFileType(.unknown) == .plainText)
    }

    @Test func asciiFileTypeMapsToAsciiArt() {
        let vm = EditorViewModel(appState: AppState(), persistenceService: MockPersistenceService())
        #expect(vm.modeForFileType(.ascii) == .asciiArt)
    }
}

// MARK: - JSONValidatorErrorModelTests

struct JSONValidatorErrorModelTests {

    @Test func errorModelStoresMessage() {
        let err = JSONValidator.JSONError(message: "Unexpected token", characterOffset: nil)
        #expect(err.message == "Unexpected token")
    }

    @Test func errorModelStoresOffset() {
        let err = JSONValidator.JSONError(message: "Error", characterOffset: 42)
        #expect(err.characterOffset == 42)
    }

    @Test func errorModelAllowsNilOffset() {
        let err = JSONValidator.JSONError(message: "Error", characterOffset: nil)
        #expect(err.characterOffset == nil)
    }
}

// MARK: - Private helpers

@MainActor
private final class MockPersistenceService: PersistenceService {
    func restore() async -> LayoutState { .default }
    func flushLayout(_: LayoutState) {}
    func flushLayoutSync(_: LayoutState) {}
    func restoreWindows() async -> [WindowDescriptor] { [] }
    func saveWindows(_: [WindowDescriptor]) {}
    func saveWindowsSync(_: [WindowDescriptor]) {}
    func writeRecovery(for: URL, content: String) {}
    func clearRecovery(for: URL) {}
    func pendingRecoveryNames() -> [String] { [] }
    func saveSetting<T: Encodable>(_: T, forKey: String) {}
    func loadSetting<T: Decodable>(forKey: String) -> T? { nil }
    func saveScratchpad(text: String) {}
    func loadScratchpadText() -> String { "" }
    func saveScratchpadDockedWidth(_: CGFloat) {}
    func loadScratchpadDockedWidth() -> CGFloat { 280 }
}
