import Foundation

/// Computed pass-throughs to the active window.
///
/// These let all existing callers written against the single-window model continue to
/// compile unchanged. Reads delegate to `activeWindow`; writes also delegate so that
/// menu commands and `SputnikCommands` work naturally.
extension AppState {

    // MARK: - Active-window pass-throughs

    public var activeWorkspaceDirectory: URL? {
        get { activeWindow?.activeWorkspaceDirectory }
        set { activeWindow?.activeWorkspaceDirectory = newValue }
    }

    public var openDocuments: [DocumentSession] {
        get { activeWindow?.openDocuments ?? [] }
        set { activeWindow?.openDocuments = newValue }
    }

    public var activeDocumentID: UUID? {
        get { activeWindow?.activeDocumentID }
        set { activeWindow?.activeDocumentID = newValue }
    }

    public var activeDocument: DocumentSession? {
        activeWindow?.activeDocument
    }

    public var currentlyOpenFile: URL? { activeDocument?.url }
    public var currentlyOpenFileType: FileType { activeDocument?.fileType ?? .unknown }

    public var layout: LayoutState {
        get { activeWindow?.layout ?? .default }
        set { activeWindow?.layout = newValue }
    }

    public var recentFiles: [URL] { layout.recentFiles }

    public var editorScrollFraction: Double? {
        get { activeWindow?.editorScrollFraction }
        set { activeWindow?.editorScrollFraction = newValue }
    }

    public var requestedHelpTarget: HelpRequest? {
        get { activeWindow?.requestedHelpTarget }
        set { activeWindow?.requestedHelpTarget = newValue }
    }

    public var requestedHelpTopic: HelpTopic? {
        get { activeWindow?.requestedHelpTopic }
        set { activeWindow?.requestedHelpTopic = newValue }
    }

    // MARK: - Document lookup

    public func document(for id: UUID) -> DocumentSession? {
        activeWindow?.document(for: id)
    }
}
