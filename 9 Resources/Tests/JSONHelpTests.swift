// JSONHelpTests.swift
// Tests for Module 9.7 JSON Help — JSONHelpContent, JSONHelpCoordinator, JSONHelpIndex,
// and SputnikCompletionCorpus JSON language support.

import Foundation
import Testing

@testable import ResourcesModule

// MARK: - JSONHelpContentTests

struct JSONHelpContentTests {

    // MARK: Happy path

    @Test func initStoresAllProperties() {
        let content = JSONHelpContent(
            id: "types/string",
            title: "Strings",
            category: "types",
            body: "JSON strings are double-quoted.",
            searchTerms: ["string", "text"],
            relatedTopics: ["types/number"],
            exampleJSON: #"{"key": "value"}"#
        )
        #expect(content.id == "types/string")
        #expect(content.title == "Strings")
        #expect(content.category == "types")
        #expect(content.body == "JSON strings are double-quoted.")
        #expect(content.searchTerms == ["string", "text"])
        #expect(content.relatedTopics == ["types/number"])
        #expect(content.exampleJSON == #"{"key": "value"}"#)
    }

    @Test func initDefaultsEmptyCollections() {
        let content = JSONHelpContent(id: "x", title: "X", category: "cat", body: "body")
        #expect(content.searchTerms.isEmpty)
        #expect(content.relatedTopics.isEmpty)
        #expect(content.exampleJSON == nil)
    }

    @Test func codableRoundTrip() throws {
        let content = JSONHelpContent(
            id: "types/null",
            title: "Null",
            category: "types",
            body: "`null` represents absence.",
            searchTerms: ["null", "nil"],
            relatedTopics: []
        )
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(JSONHelpContent.self, from: data)
        #expect(decoded.id == "types/null")
        #expect(decoded.title == "Null")
        #expect(decoded.searchTerms == ["null", "nil"])
    }

    @Test func codableWithNilExampleJSON() throws {
        let content = JSONHelpContent(id: "a", title: "A", category: "c", body: "b")
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(JSONHelpContent.self, from: data)
        #expect(decoded.exampleJSON == nil)
    }
}

// MARK: - JSONHelpIndexFileTests

struct JSONHelpIndexFileTests {

    @Test func codableRoundTrip() throws {
        let topics = [
            JSONHelpContent(id: "t1", title: "T1", category: "cat", body: "body"),
            JSONHelpContent(id: "t2", title: "T2", category: "cat", body: "body2"),
        ]
        let file = JSONHelpIndexFile(topics: topics)
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(JSONHelpIndexFile.self, from: data)
        #expect(decoded.topics.count == 2)
        #expect(decoded.topics[0].id == "t1")
        #expect(decoded.topics[1].id == "t2")
    }
}

// MARK: - JSONHelpCoordinatorTests

@MainActor
struct JSONHelpCoordinatorTests {

    // MARK: Selected text lookup

    @Test func selectedStringMatchesStringTopic() {
        let coordinator = JSONHelpCoordinator.shared
        let result = coordinator.lookupContext(fullText: "", cursorOffset: 0, selectedText: "string")
        #expect(result == "types/string")
    }

    @Test func selectedNumberMatchesNumberTopic() {
        let coordinator = JSONHelpCoordinator.shared
        let result = coordinator.lookupContext(fullText: "", cursorOffset: 0, selectedText: "number")
        #expect(result == "types/number")
    }

    @Test func selectedBooleanMatchesBooleanTopic() {
        let coordinator = JSONHelpCoordinator.shared
        let result = coordinator.lookupContext(fullText: "", cursorOffset: 0, selectedText: "boolean")
        #expect(result == "types/boolean")
    }

    @Test func selectedTrueMatchesBooleanTopic() {
        let coordinator = JSONHelpCoordinator.shared
        let result = coordinator.lookupContext(fullText: "", cursorOffset: 0, selectedText: "true")
        #expect(result == "types/boolean")
    }

    @Test func selectedFalseMatchesBooleanTopic() {
        let coordinator = JSONHelpCoordinator.shared
        let result = coordinator.lookupContext(fullText: "", cursorOffset: 0, selectedText: "false")
        #expect(result == "types/boolean")
    }

    @Test func selectedNullMatchesNullTopic() {
        let coordinator = JSONHelpCoordinator.shared
        let result = coordinator.lookupContext(fullText: "", cursorOffset: 0, selectedText: "null")
        #expect(result == "types/null")
    }

    @Test func selectedArrayMatchesArrayTopic() {
        let coordinator = JSONHelpCoordinator.shared
        let result = coordinator.lookupContext(fullText: "", cursorOffset: 0, selectedText: "array")
        #expect(result == "types/array")
    }

    @Test func selectedObjectMatchesObjectTopic() {
        let coordinator = JSONHelpCoordinator.shared
        let result = coordinator.lookupContext(fullText: "", cursorOffset: 0, selectedText: "object")
        #expect(result == "types/object")
    }

    @Test func selectedSchemaMatchesSchemaTopic() {
        let coordinator = JSONHelpCoordinator.shared
        let result = coordinator.lookupContext(fullText: "", cursorOffset: 0, selectedText: "schema")
        #expect(result == "patterns/schema")
    }

    @Test func selectedPrettyMatchesFormattingTopic() {
        let coordinator = JSONHelpCoordinator.shared
        let result = coordinator.lookupContext(fullText: "", cursorOffset: 0, selectedText: "pretty")
        #expect(result == "tools/formatting")
    }

    // MARK: Case insensitivity

    @Test func uppercasedSelectionStillMatches() {
        let coordinator = JSONHelpCoordinator.shared
        let result = coordinator.lookupContext(fullText: "", cursorOffset: 0, selectedText: "STRING")
        #expect(result == "types/string")
    }

    // MARK: No match

    @Test func unknownTokenReturnsNil() {
        let coordinator = JSONHelpCoordinator.shared
        let result = coordinator.lookupContext(fullText: "", cursorOffset: 0, selectedText: "xyzzy")
        #expect(result == nil)
    }

    @Test func emptySelectionReturnsNilOrFallsBackToCursor() {
        let coordinator = JSONHelpCoordinator.shared
        let result = coordinator.lookupContext(fullText: "", cursorOffset: 0, selectedText: "")
        #expect(result == nil)
    }
}

// MARK: - SputnikCompletionCorpusJSONTests

struct SputnikCompletionCorpusJSONTests {

    @Test func jsonLanguageReturnsResultsForKnownPrefix() async {
        let corpus = SputnikCompletionCorpus()
        let query = CompletionQuery(language: .json, prefix: "str", limit: 5)
        let results = await corpus.completions(query)
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.lowercased().hasPrefix("str") })
    }

    @Test func jsonLanguageShortPrefixReturnsEmpty() async {
        let corpus = SputnikCompletionCorpus()
        let query = CompletionQuery(language: .json, prefix: "s", limit: 5)
        let results = await corpus.completions(query)
        #expect(results.isEmpty)
    }

    @Test func jsonLanguagePrefixNumReturnsResults() async {
        let corpus = SputnikCompletionCorpus()
        let query = CompletionQuery(language: .json, prefix: "num", limit: 5)
        let results = await corpus.completions(query)
        #expect(!results.isEmpty)
    }

    @Test func jsonLanguageExactMatchExcluded() async {
        let corpus = SputnikCompletionCorpus()
        let query = CompletionQuery(language: .json, prefix: "string", limit: 5)
        let results = await corpus.completions(query)
        #expect(!results.contains("string"))
    }

    @Test func jsonLanguageEmptyPrefixReturnsEmpty() async {
        let corpus = SputnikCompletionCorpus()
        let query = CompletionQuery(language: .json, prefix: "", limit: 5)
        let results = await corpus.completions(query)
        #expect(results.isEmpty)
    }

    @Test func jsonLanguageUnknownPrefixReturnsEmpty() async {
        let corpus = SputnikCompletionCorpus()
        let query = CompletionQuery(language: .json, prefix: "xyzzy", limit: 5)
        let results = await corpus.completions(query)
        #expect(results.isEmpty)
    }

    @Test func jsonLanguageLimitRespected() async {
        let corpus = SputnikCompletionCorpus()
        let query = CompletionQuery(language: .json, prefix: "s", limit: 5)
        let results = await corpus.completions(query)
        #expect(results.count <= 5)
    }
}

// MARK: - WritingAssistMatrixJSONTests

struct WritingAssistMatrixJSONTests {

    @Test func jsonAutoCompleteIsApplicable() {
        #expect(WritingAssistMatrix.applies(.autoComplete, to: .json))
    }

    @Test func jsonMoreContextIsApplicable() {
        #expect(WritingAssistMatrix.applies(.moreContext, to: .json))
    }

    @Test func jsonInstantCorrectIsNotApplicable() {
        #expect(!WritingAssistMatrix.applies(.instantCorrect, to: .json))
    }

    @Test func defaultMatrixHasJSONAutoCompleteOn() {
        let m = WritingAssistMatrix.default
        #expect(m.isEnabled(.autoComplete, for: .json))
    }

    @Test func defaultMatrixHasJSONMoreContextOn() {
        let m = WritingAssistMatrix.default
        #expect(m.isEnabled(.moreContext, for: .json))
    }

    @Test func jsonInstantCorrectAlwaysReturnsFalse() {
        let m = WritingAssistMatrix.default
        #expect(!m.isEnabled(.instantCorrect, for: .json))
    }
}
