import AppIntents
import AppKit

/// Opens a file in Sputnik.
struct OpenFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Open File"
    static let description = LocalizedStringResource("Opens a file in Sputnik's editor")
    static let openAppWhenRun = true

    @Parameter(title: "File URL")
    var fileURL: URL?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard fileURL != nil else {
            throw $fileURL.needsValueError(.init("Which file would you like to open?"))
        }
        // The IntentHandler in the .appex extension routes to AppState.
        return .result()
    }
}
