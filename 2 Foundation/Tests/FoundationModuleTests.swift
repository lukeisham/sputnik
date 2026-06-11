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
