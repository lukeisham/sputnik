import AppIntents
import AppKit

/// Opens a new untitled document in Sputnik.
struct NewDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "New Document"
    static let description = LocalizedStringResource("Creates a new untitled document in Sputnik")
    static let openAppWhenRun = true

    @Parameter(title: "File Type")
    var fileType: DocumentType?

    @MainActor
    func perform() async throws -> some IntentResult {
        // Route to Sputnik's main app. The IntentHandler in the .appex extension
        // will bridge this to AppState via shared container or XPC.
        return .result()
    }
}

enum DocumentType: String, AppEnum {
    case plainText
    case markdown
    case html

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "File Type"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .plainText: "Plain Text",
        .markdown: "Markdown",
        .html: "HTML",
    ]
}
