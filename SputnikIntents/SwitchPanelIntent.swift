import AppIntents
import AppKit

/// Switches to a specific panel in Sputnik.
struct SwitchPanelIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Panel"
    static let description = LocalizedStringResource("Switches Sputnik to the specified panel")
    static let openAppWhenRun = true

    @Parameter(title: "Panel")
    var panel: PanelType?

    @MainActor
    func perform() async throws -> some IntentResult {
        // The IntentHandler in the .appex extension routes to the appropriate panel.
        return .result()
    }
}

enum PanelType: String, AppEnum {
    case editor
    case fileTree
    case markdownPreview
    case htmlPreview
    case pdfViewer
    case terminal

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Panel"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .editor: "Text Editor",
        .fileTree: "File Tree",
        .markdownPreview: "Markdown Preview",
        .htmlPreview: "HTML Preview",
        .pdfViewer: "PDF Viewer",
        .terminal: "Terminal",
    ]
}
