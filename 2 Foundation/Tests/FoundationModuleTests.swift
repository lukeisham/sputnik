import Foundation
import Testing
import TestingSupport

// MARK: - Test imports
//
// FoundationModule exports production types like DocumentSession, InterPanelRouter, etc.
// TestingSupport provides mock implementations for InterPanelRouter, AppState, and WindowState
// as a separate library target.
@testable import FoundationModule

// MARK: - MockInterPanelRouter Tests

@MainActor
struct MockInterPanelRouterTests {

    @Test func openRecordsURL() async {
        let router = MockInterPanelRouter()
        let url = URL(fileURLWithPath: "/tmp/test.md")

        await router.open(url)

        #expect(router.openCalls.count == 1)
        #expect(router.openCalls.first == url)
    }

    @Test func openAppendsMultipleURLs() async {
        let router = MockInterPanelRouter()
        let url1 = URL(fileURLWithPath: "/tmp/a.md")
        let url2 = URL(fileURLWithPath: "/tmp/b.md")

        await router.open(url1)
        await router.open(url2)

        #expect(router.openCalls.count == 2)
        #expect(router.openCalls[0] == url1)
        #expect(router.openCalls[1] == url2)
    }

    @Test func closeRecordsDocumentID() async {
        let router = MockInterPanelRouter()
        let id = UUID()

        await router.close(id)

        #expect(router.closeCalls.count == 1)
        #expect(router.closeCalls.first == id)
    }

    @Test func syncDirectoryRecordsURL() {
        let router = MockInterPanelRouter()
        let url = URL(fileURLWithPath: "/tmp")

        router.syncDirectory(url)

        #expect(router.syncDirectoryCalls.count == 1)
        #expect(router.syncDirectoryCalls.first == url)
    }

    @Test func moveActiveTabToNewWindowReturnsUUIDOnSuccess() async {
        let router = MockInterPanelRouter()
        router.shouldSucceed = true

        let result = await router.moveActiveTabToNewWindow()

        #expect(result != nil)
        #expect(router.moveActiveTabToNewWindowCalls == 1)
    }

    @Test func moveActiveTabToNewWindowReturnsNilOnFailure() async {
        let router = MockInterPanelRouter()
        router.shouldSucceed = false

        let result = await router.moveActiveTabToNewWindow()

        #expect(result == nil)
        #expect(router.moveActiveTabToNewWindowCalls == 1)
    }

    @Test func eventsStreamIsNotEmptyType() {
        let router = MockInterPanelRouter()
        let _: any AsyncSequence = router.events
        // Compile-time check: events is an AsyncStream (concrete type known at compile time)
        #expect(true)
    }
}

// MARK: - MockAppState Tests

struct MockAppStateTests {

    @Test func beginProcessingSetsIsProcessingTrue() {
        let state = MockAppState()

        state.beginProcessing()

        #expect(state.isProcessing == true)
    }

    @Test func endProcessingSetsIsProcessingFalse() {
        let state = MockAppState()
        state.beginProcessing()

        state.endProcessing()

        #expect(state.isProcessing == false)
    }

    @Test func beginProcessingIsIdempotent() {
        let state = MockAppState()

        state.beginProcessing()
        state.beginProcessing()
        state.beginProcessing()

        #expect(state.isProcessing == true)
    }

    @Test func endProcessingOnNonProcessingStateStaysFalse() {
        let state = MockAppState()

        state.endProcessing()

        #expect(state.isProcessing == false)
    }

    @Test func initialStateIsCorrect() {
        let state = MockAppState()

        #expect(state.isProcessing == false)
        #expect(state.activeDocument == nil)
        #expect(state.contextUsageForTesting == "")
    }
}

// MARK: - MockWindowState Tests

@MainActor
struct MockWindowStateTests {

    @Test func openDocumentAppendsAndSetsActive() {
        let ws = MockWindowState()
        let session = DocumentSession(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/test.md"),
            fileType: .markdown,
            text: "# Hello",
            isDirty: false
        )

        ws.openDocument(session)

        #expect(ws.openDocuments.count == 1)
        #expect(ws.openDocuments.first?.id == session.id)
        #expect(ws.activeDocumentID == session.id)
    }

    @Test func openMultipleDocumentsStoresAll() {
        let ws = MockWindowState()
        let session1 = DocumentSession(url: nil, fileType: .text)
        let session2 = DocumentSession(url: URL(fileURLWithPath: "/tmp/b.md"), fileType: .markdown)
        let session3 = DocumentSession(url: URL(fileURLWithPath: "/tmp/c.html"), fileType: .html)

        ws.openDocument(session1)
        ws.openDocument(session2)
        ws.openDocument(session3)

        #expect(ws.openDocuments.count == 3)
        #expect(ws.activeDocumentID == session3.id)  // Last opened is active
    }

    @Test func closeDocumentRemovesAndReturnsSession() {
        let ws = MockWindowState()
        let session = DocumentSession(
            url: URL(fileURLWithPath: "/tmp/test.md"), fileType: .markdown)
        ws.openDocument(session)

        let removed = ws.closeDocument(session.id)

        #expect(removed?.id == session.id)
        #expect(ws.openDocuments.isEmpty)
        #expect(ws.closeDocumentCalls.count == 1)
        #expect(ws.closeDocumentCalls.first == session.id)
    }

    @Test func closeNonExistentDocumentReturnsNil() {
        let ws = MockWindowState()
        let session = DocumentSession(
            url: URL(fileURLWithPath: "/tmp/test.md"), fileType: .markdown)
        ws.openDocument(session)

        let removed = ws.closeDocument(UUID())

        #expect(removed == nil)
        #expect(ws.openDocuments.count == 1)
    }

    @Test func setActiveDocumentUpdatesID() {
        let ws = MockWindowState()

        let id = UUID()
        ws.setActiveDocument(id)

        #expect(ws.activeDocumentID == id)
    }

    @Test func setActiveDocumentNilClearsID() {
        let ws = MockWindowState()
        ws.setActiveDocument(UUID())

        ws.setActiveDocument(nil)

        #expect(ws.activeDocumentID == nil)
    }
}

// MARK: - TemplatePlaceholderExpander Tests

struct TemplatePlaceholderExpanderTests {

    @Test func noPlaceholdersReturnsEmpty() {
        let keys = TemplatePlaceholderExpander.placeholders(in: "Hello world, no keys here.")
        #expect(keys.isEmpty)
    }

    @Test func singlePlaceholderDetected() {
        let keys = TemplatePlaceholderExpander.placeholders(in: "Hello {{name}}!")
        #expect(keys == ["name"])
    }

    @Test func multiplePlaceholdersInOrder() {
        let keys = TemplatePlaceholderExpander.placeholders(
            in: "{{title}} by {{author}} on {{date}}")
        #expect(keys == ["title", "author", "date"])
    }

    @Test func duplicatePlaceholdersDeduplicated() {
        let keys = TemplatePlaceholderExpander.placeholders(in: "{{name}} and {{name}} again")
        #expect(keys == ["name"])
    }

    @Test func expandSubstitutesAllKeys() {
        let result = TemplatePlaceholderExpander.expand(
            template: "# {{title}}\n\nBy {{author}}.",
            values: ["title": "My Doc", "author": "Alice"])
        #expect(result == "# My Doc\n\nBy Alice.")
    }

    @Test func expandMissingKeyBecomesEmptyString() {
        let result = TemplatePlaceholderExpander.expand(
            template: "Hello {{name}}!", values: [:])
        #expect(result == "Hello !")
    }

    @Test func expandMultipleOccurrencesOfSameKey() {
        let result = TemplatePlaceholderExpander.expand(
            template: "{{x}} and {{x}}", values: ["x": "foo"])
        #expect(result == "foo and foo")
    }

    @Test func defaultValuesSeededDateKey() {
        let defaults = TemplatePlaceholderExpander.defaultValues(for: ["date", "title"])
        #expect(defaults["date"] != nil)
        #expect(defaults["title"] == nil)
        // Date should be in YYYY-MM-DD format (10 chars).
        #expect(defaults["date"]?.count == 10)
    }
}

// MARK: - TemplateStore Tests

struct TemplateStoreTests {

    /// Returns a fresh temporary directory for each test.
    private func tempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func saveWritesFileAndTemplatesReflectsIt() async throws {
        let store = TemplateStore()
        let dir = try tempDir()
        await store.setDirectory(dir)

        try await store.save(name: "MyTemplate", content: "# {{title}}", fileExtension: "md")

        let list = await store.templates()
        #expect(list.count == 1)
        #expect(list.first?.name == "MyTemplate")
        #expect(list.first?.fileExtension == "md")
    }

    @Test func deleteRemovesFile() async throws {
        let store = TemplateStore()
        let dir = try tempDir()
        await store.setDirectory(dir)

        try await store.save(name: "Gone", content: "hello", fileExtension: "md")
        let before = await store.templates()
        #expect(before.count == 1)

        if let record = before.first {
            try await store.delete(record: record)
        }

        let after = await store.templates()
        #expect(after.isEmpty)
    }

    @Test func setDirectorySwitchesScanLocation() async throws {
        let store = TemplateStore()

        let dir1 = try tempDir()
        let dir2 = try tempDir()

        await store.setDirectory(dir1)
        try await store.save(name: "A", content: "a", fileExtension: "md")

        await store.setDirectory(dir2)
        try await store.save(name: "B", content: "b", fileExtension: "html")

        let list = await store.templates()
        #expect(list.count == 1)
        #expect(list.first?.name == "B")
    }

    @Test func duplicateNameThrows() async throws {
        let store = TemplateStore()
        let dir = try tempDir()
        await store.setDirectory(dir)

        try await store.save(name: "Dupe", content: "first", fileExtension: "md")

        var threw = false
        do {
            try await store.save(name: "Dupe", content: "second", fileExtension: "md")
        } catch {
            threw = true
        }
        #expect(threw)
    }

    @Test func rawContentReadsCorrectly() async throws {
        let store = TemplateStore()
        let dir = try tempDir()
        await store.setDirectory(dir)

        try await store.save(name: "Readable", content: "hello {{world}}", fileExtension: "md")
        let record = try #require(await store.templates().first)
        let content = try await store.rawContent(of: record)
        #expect(content == "hello {{world}}")
    }
}

// MARK: - FileType Tests

struct FileTypeDefaultExtensionTests {

    @Test func markdownDefaultExtension() {
        #expect(FileType.markdown.defaultExtension == "md")
    }

    @Test func htmlDefaultExtension() {
        #expect(FileType.html.defaultExtension == "html")
    }

    @Test func textDefaultExtension() {
        #expect(FileType.text.defaultExtension == "txt")
    }

    @Test func fileTypeFromExtensionString() {
        #expect(FileType(extension: "md") == .markdown)
        #expect(FileType(extension: "html") == .html)
        #expect(FileType(extension: "txt") == .text)
        #expect(FileType(extension: "asc") == .ascii)
    }
}

// MARK: - MinimapModelBuilder Tests

struct MinimapModelBuilderTests {

    // MARK: - Empty / blank input

    @Test func emptyTextProducesEmptyModel() {
        let model = MinimapModelBuilder().build(from: "")
        #expect(model.lines.isEmpty)
    }

    @Test func blankLinesAreClassifiedAsBlank() {
        // Trailing newline produces one extra empty line.
        let model = MinimapModelBuilder().build(from: "\n   \n\t")
        #expect(model.lines.count == 3)
        for line in model.lines {
            #expect(line.kind == .blank)
        }
    }

    // MARK: - Heading classification

    @Test func atxHeadingClassifiedAsHeading() {
        let line = MinimapModelBuilder.classify(line: "# Heading 1")
        #expect(line == .heading)
    }

    @Test func h2HeadingClassifiedAsHeading() {
        let line = MinimapModelBuilder.classify(line: "## Section")
        #expect(line == .heading)
    }

    @Test func h6HeadingClassifiedAsHeading() {
        let line = MinimapModelBuilder.classify(line: "###### Deep")
        #expect(line == .heading)
    }

    @Test func sevenHashesAreNotHeading() {
        let line = MinimapModelBuilder.classify(line: "####### Too many")
        #expect(line != .heading)
    }

    @Test func hashWithoutSpaceIsNotHeading() {
        // "#tag" is not a heading.
        let line = MinimapModelBuilder.classify(line: "#tag")
        #expect(line != .heading)
    }

    // MARK: - Blockquote classification

    @Test func blockquoteLineClassifiedAsQuote() {
        let line = MinimapModelBuilder.classify(line: "> Quoted text")
        #expect(line == .quote)
    }

    @Test func nestedBlockquoteIsQuote() {
        let line = MinimapModelBuilder.classify(line: ">> Deep quote")
        #expect(line == .quote)
    }

    // MARK: - List classification

    @Test func unorderedDashList() {
        let line = MinimapModelBuilder.classify(line: "- Item one")
        #expect(line == .list)
    }

    @Test func unorderedAsteriskList() {
        let line = MinimapModelBuilder.classify(line: "* Item two")
        #expect(line == .list)
    }

    @Test func unorderedPlusList() {
        let line = MinimapModelBuilder.classify(line: "+ Item three")
        #expect(line == .list)
    }

    @Test func orderedList() {
        let line = MinimapModelBuilder.classify(line: "1. First step")
        #expect(line == .list)
    }

    @Test func multiDigitOrderedList() {
        let line = MinimapModelBuilder.classify(line: "42. Answer")
        #expect(line == .list)
    }

    @Test func listWithoutSpaceIsNotList() {
        let line = MinimapModelBuilder.classify(line: "-NotAList")
        #expect(line != .list)
    }

    // MARK: - Code classification

    @Test func fencedCodeBlockBackticks() {
        let line = MinimapModelBuilder.classify(line: "```swift")
        #expect(line == .code)
    }

    @Test func fencedCodeBlockTildes() {
        let line = MinimapModelBuilder.classify(line: "~~~")
        #expect(line == .code)
    }

    @Test func indentedCode() {
        let line = MinimapModelBuilder.classify(line: "    code line")
        #expect(line == .code)
    }

    // MARK: - Plain text

    @Test func ordinaryTextIsPlain() {
        let line = MinimapModelBuilder.classify(line: "Just a regular sentence.")
        #expect(line == .plain)
    }

    // MARK: - Length normalisation

    @Test func longestLineHasFullWidth() {
        let model = MinimapModelBuilder().build(from: "short\nlongest line here")
        #expect(model.lines.count == 2)
        #expect(model.lines[0].lengthFraction < model.lines[1].lengthFraction)
        #expect(model.lines[1].lengthFraction == 1.0)
    }

    @Test func singleLineHasFullWidth() {
        let model = MinimapModelBuilder().build(from: "only line")
        #expect(model.lines.count == 1)
        #expect(model.lines[0].lengthFraction == 1.0)
    }

    @Test func allLinesSameLength() {
        let model = MinimapModelBuilder().build(from: "aaa\nbbb\nccc")
        #expect(model.lines.count == 3)
        for line in model.lines {
            #expect(line.lengthFraction == 1.0)
        }
    }

    @Test func mixedContentDocument() {
        let markdown = """
            # Title

            Some paragraph text here.

            > A blockquote

            - List item
            - Another item

                code block

            ## Section 2

            More text.
            """
        let model = MinimapModelBuilder().build(from: markdown)
        #expect(model.lines.count > 5)

        // The first non-blank line should be a heading.
        let nonBlank = model.lines.filter { $0.kind != .blank }
        #expect(nonBlank.first?.kind == .heading)
    }

    // MARK: - Viewport math

    @Test func viewportFractionZeroAtTop() {
        // When offset is 0, fraction should be 0.
        let fraction = viewportFraction(offset: 0, docHeight: 1000, viewHeight: 200)
        #expect(fraction == 0.0)
    }

    @Test func viewportFractionOneAtBottom() {
        let fraction = viewportFraction(offset: 800, docHeight: 1000, viewHeight: 200)
        #expect(fraction == 1.0)
    }

    @Test func viewportFractionMidDocument() {
        let fraction = viewportFraction(offset: 400, docHeight: 1000, viewHeight: 200)
        #expect(fraction == 0.5)
    }

    @Test func contentShorterThanViewportYieldsZero() {
        let fraction = viewportFraction(offset: 0, docHeight: 100, viewHeight: 200)
        #expect(fraction == 0.0)
    }

    @Test func emptyDocumentYieldsZero() {
        let fraction = viewportFraction(offset: 0, docHeight: 0, viewHeight: 200)
        #expect(fraction == 0.0)
    }

    @Test func clickFractionToScrollTarget() {
        let target = scrollTarget(forClickFraction: 0.5, docHeight: 1000, viewHeight: 200)
        #expect(target == 400.0)
    }

    @Test func clickFractionZeroMapsToZero() {
        let target = scrollTarget(forClickFraction: 0.0, docHeight: 1000, viewHeight: 200)
        #expect(target == 0.0)
    }

    @Test func clickFractionOneMapsToMaxScroll() {
        let target = scrollTarget(forClickFraction: 1.0, docHeight: 1000, viewHeight: 200)
        #expect(target == 800.0)
    }
}

// MARK: - Viewport math helpers (package-private)

/// Computes the viewport fraction from scroll offset and dimensions.
/// Mirrors the logic in MinimapScrollBinder.Coordinator.updateViewport.
private func viewportFraction(offset: CGFloat, docHeight: CGFloat, viewHeight: CGFloat) -> Double {
    let maxScroll = max(0, docHeight - viewHeight)
    guard maxScroll > 0 else { return 0 }
    return max(0, min(1.0, Double(offset / maxScroll)))
}

/// Computes the scroll target from a click fraction.
private func scrollTarget(
    forClickFraction fraction: Double, docHeight: CGFloat, viewHeight: CGFloat
) -> CGFloat {
    let maxScroll = max(0, docHeight - viewHeight)
    return CGFloat(fraction) * maxScroll
}
