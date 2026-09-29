import CoreGraphics
import Foundation
import Testing

@testable import FoundationModule

// Saved user data must survive the removal of a feature (plan "Replace spelling and
// grammar with Apple's checker", 1 of 4). These tests cover the three places where a
// removed value could silently reset or break user data: the saved layout, the
// writing-assist matrix, and the spelling settings.

// MARK: - Test helpers

/// An in-memory `PersistenceService` that stores settings as JSON, the same as the real one.
@MainActor
private final class InMemoryPersistence: PersistenceService {
    var settings: [String: Data] = [:]

    func restore() async -> LayoutState { .default }
    func flushLayout(_: LayoutState) {}
    func flushLayoutSync(_: LayoutState) {}
    func restoreWindows() async -> [WindowDescriptor] { [] }
    func saveWindows(_: [WindowDescriptor]) {}
    func saveWindowsSync(_: [WindowDescriptor]) {}
    func writeRecovery(for: URL, content: String) {}
    func clearRecovery(for: URL) {}
    func pendingRecoveryNames() -> [String] { [] }
    func saveSetting<T: Encodable>(_ value: T, forKey key: String) {
        settings[key] = try? JSONEncoder().encode(value)
    }
    func loadSetting<T: Decodable>(forKey key: String) -> T? {
        guard let data = settings[key] else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    func saveScratchpad(text: String) {}
    func loadScratchpadText() -> String { "" }
    func saveScratchpadDockedWidth(_: CGFloat) {}
    func loadScratchpadDockedWidth() -> CGFloat { 280 }
}

private enum LayoutJSONError: Error { case unexpectedShape }

/// Encodes `state`, lets `edit` change the column list as raw JSON, and returns the bytes.
private func layoutJSON(
    _ state: LayoutState,
    edit: (inout [[String: Any]]) -> Void
) throws -> Data {
    let data = try JSONEncoder().encode(state)
    guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        var dynamic = root["dynamicLayout"] as? [String: Any],
        var columns = dynamic["columns"] as? [[String: Any]]
    else { throw LayoutJSONError.unexpectedShape }
    edit(&columns)
    dynamic["columns"] = columns
    root["dynamicLayout"] = dynamic
    return try JSONSerialization.data(withJSONObject: root)
}

private func threeColumnState() -> LayoutState {
    LayoutState(
        dynamicLayout: DynamicPanelLayout(columns: [
            PanelColumn(renderMode: .fileTree, width: 0.2),
            PanelColumn(renderMode: .textEditor, width: 0.5),
            PanelColumn(renderMode: .markdownPreview, width: 0.3),
        ]),
        terminalVisible: false,
        recentFiles: [],
        openDocumentURLs: [],
        activeDocumentURL: nil
    )
}

// MARK: - Layout decoding

struct LayoutUnknownPanelTests {

    @Test func removedPanelColumnIsDroppedAndOthersSurvive() throws {
        let data = try layoutJSON(threeColumnState()) { columns in
            columns[2]["renderMode"] = "grammarHelp"
        }
        let decoded = try JSONDecoder().decode(LayoutState.self, from: data)
        let modes = decoded.dynamicLayout.columns.map(\.renderMode)
        #expect(modes == [.fileTree, .textEditor])
        // Other fields are not reset to the default.
        #expect(decoded.terminalVisible == false)
    }

    @Test func widthsAreRescaledAfterADroppedColumn() throws {
        let data = try layoutJSON(threeColumnState()) { columns in
            columns[2]["renderMode"] = "grammarHelp"
        }
        let decoded = try JSONDecoder().decode(LayoutState.self, from: data)
        let total = decoded.dynamicLayout.columns.map(\.width).reduce(0, +)
        #expect(abs(total - 1.0) < 0.0001)
    }

    @Test func unknownOriginalRenderModeKeepsTheColumn() throws {
        let data = try layoutJSON(threeColumnState()) { columns in
            columns[1]["originalRenderMode"] = "grammarHelp"
        }
        let decoded = try JSONDecoder().decode(LayoutState.self, from: data)
        #expect(decoded.dynamicLayout.columns.count == 3)
        #expect(decoded.dynamicLayout.columns[1].originalRenderMode == nil)
    }

    @Test func layoutWithOnlyUnknownPanelsFallsBackToDefault() throws {
        let data = try layoutJSON(threeColumnState()) { columns in
            for i in columns.indices { columns[i]["renderMode"] = "grammarHelp" }
        }
        let decoded = try JSONDecoder().decode(LayoutState.self, from: data)
        #expect(decoded.dynamicLayout.columns.map(\.renderMode)
            == DynamicPanelLayout.default.columns.map(\.renderMode))
    }

    @Test func knownLayoutRoundTrips() throws {
        let state = threeColumnState()
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(LayoutState.self, from: data)
        #expect(decoded.dynamicLayout == state.dynamicLayout)
    }
}

// MARK: - Writing-assist matrix decoding

struct WritingAssistMatrixLegacyTests {

    /// JSON saved by a version that still had spelling, grammar and Instant Correct.
    private let legacyJSON = """
        {"cells": {
            "instantCorrect.spelling": true,
            "instantCorrect.grammar": false,
            "autoComplete.spelling": true,
            "moreContext.grammar": true,
            "interaction.grammar": true,
            "autoComplete.markdown": false,
            "moreContext.style": true
        }}
        """

    @Test func oldMatrixJSONDecodesWithoutError() throws {
        let matrix = try JSONDecoder().decode(
            WritingAssistMatrix.self, from: Data(legacyJSON.utf8))
        // Cells that still exist keep their saved value.
        #expect(matrix.isEnabled(.autoComplete, for: .markdown) == false)
        #expect(matrix.isEnabled(.moreContext, for: .style) == true)
    }

    @Test func oldMatrixDoesNotChangeApplicability() throws {
        let matrix = try JSONDecoder().decode(
            WritingAssistMatrix.self, from: Data(legacyJSON.utf8))
        for lang in WritingAssistLanguage.allCases {
            for fn in WritingAssistFunction.allCases where !WritingAssistMatrix.applies(fn, to: lang) {
                #expect(matrix.isEnabled(fn, for: lang) == false)
            }
        }
    }

    @Test func spellingAndGrammarAreNotMatrixLanguages() {
        #expect(WritingAssistLanguage(rawValue: "spelling") == nil)
        #expect(WritingAssistLanguage(rawValue: "grammar") == nil)
        #expect(WritingAssistFunction(rawValue: "instantCorrect") == nil)
    }
}

// MARK: - Apple checker settings

@MainActor
struct SystemSpellingSettingsTests {

    @Test func defaultsAreSpellingOnGrammarOff() {
        let settings = SettingsStore(persistence: InMemoryPersistence())
        #expect(settings.systemSpellCheckEnabled == true)
        #expect(settings.systemGrammarCheckEnabled == false)
    }

    @Test func oldKeysKeepTheUsersChoice() {
        let persistence = InMemoryPersistence()
        persistence.saveSetting(false, forKey: "sputnik.settings.spellCheck")
        persistence.saveSetting(true, forKey: "sputnik.settings.grammarCheck")
        let settings = SettingsStore(persistence: persistence)
        #expect(settings.systemSpellCheckEnabled == false)
        #expect(settings.systemGrammarCheckEnabled == true)
    }

    @Test func settersPersistAcrossRestart() {
        let persistence = InMemoryPersistence()
        let first = SettingsStore(persistence: persistence)
        first.setSystemSpellCheckEnabled(false)
        first.setSystemGrammarCheckEnabled(true)

        let second = SettingsStore(persistence: persistence)
        #expect(second.systemSpellCheckEnabled == false)
        #expect(second.systemGrammarCheckEnabled == true)
    }
}
