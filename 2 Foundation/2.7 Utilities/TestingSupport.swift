import Foundation
import FoundationModule

// MARK: - Mock InterPanelRouter

/// Mock router for testing module logic that calls `InterPanelRouter.open(_:)`.
public final class MockInterPanelRouter: InterPanelRouter {
    public var events: AsyncStream<PanelEvent> {
        AsyncStream { _ in }
    }
    public var openCalls: [URL] = []
    public var closeCalls: [UUID] = []
    public var syncDirectoryCalls: [URL] = []
    public var moveActiveTabToNewWindowCalls: Int = 0

    public var shouldSucceed = true

    public init() {}

    public func open(_ fileURL: URL) async {
        openCalls.append(fileURL)
    }

    public func close(_ documentID: UUID) async {
        closeCalls.append(documentID)
    }

    public func syncDirectory(_ directoryURL: URL) {
        syncDirectoryCalls.append(directoryURL)
    }

    public func moveActiveTabToNewWindow() async -> UUID? {
        moveActiveTabToNewWindowCalls += 1
        return shouldSucceed ? UUID() : nil
    }
}

// MARK: - Mock AppState

/// Mock app state for testing components that depend on `AppState`.
public final class MockAppState {
    public var activeDocument: DocumentSession?
    public var activeWindowID: UUID = UUID()
    public var isProcessing: Bool = false
    public var requestedHelpTarget: HelpRequest?
    public var contextUsageForTesting: String = ""

    public init() {}

    public func beginProcessing() {
        isProcessing = true
    }

    public func endProcessing() {
        isProcessing = false
    }
}

// MARK: - Mock WindowState

/// Mock window state for testing window-level logic.
@MainActor
public final class MockWindowState {
    public var windowID: UUID = UUID()
    public var title: String = "Test Window"
    public var openDocuments: [DocumentSession] = []
    public var activeDocumentID: UUID?
    public var dynamicLayout: DynamicPanelLayout = .default

    public var moveDocumentCalls: [(from: IndexSet, to: Int)] = []
    public var closeDocumentCalls: [UUID] = []

    public init() {}

    public func openDocument(_ session: DocumentSession) {
        openDocuments.append(session)
        activeDocumentID = session.id
    }

    public func closeDocument(_ id: UUID) -> DocumentSession? {
        if let index = openDocuments.firstIndex(where: { $0.id == id }) {
            closeDocumentCalls.append(id)
            return openDocuments.remove(at: index)
        }
        return nil
    }

    public func moveDocument(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty else { return }
        moveDocumentCalls.append((from: source, to: destination))
        openDocuments.move(fromOffsets: source, toOffset: destination)
    }

    public func setActiveDocument(_ id: UUID?) {
        activeDocumentID = id
    }
}
