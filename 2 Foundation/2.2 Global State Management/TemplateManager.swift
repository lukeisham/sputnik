import Foundation
import Observation

/// Owns all template-related state and async operations (2.10).
///
/// Extracted from `AppState` (SR-6) so templates have an independently testable home.
/// The manager is decoupled from window management: when a template needs to be opened
/// as a new document it calls back through `onOpenDocument`, which `AppState` wires to
/// its own `openTemplateDocument(content:fileExtension:)` during init.
///
/// **Threading:** `@MainActor` — all state mutations happen on the main thread.
@Observable
@MainActor
public final class TemplateManager {

    /// The list of available templates in the current template directory.
    /// Refreshed at launch and whenever the directory changes or a template is saved/deleted.
    public var availableTemplates: [TemplateRecord] = []

    /// Non-nil when the user has selected a template that contains placeholders.
    /// Setting this triggers the placeholder-expansion sheet in `ContentView`.
    public var templatePendingRequest: TemplatePendingRequest?

    /// Non-nil when a template operation fails; drives an alert in `ContentView`.
    public var templateError: SputnikAlert?

    /// Called when a template with no placeholders should be opened as a new document.
    /// Signature: `(content: String, fileExtension: String) -> Void`.
    /// Wired by `AppState` to route back to its window-aware document creation.
    public var onOpenDocument: ((String, String) -> Void)?

    public init() {}

    /// Reloads `availableTemplates` from `TemplateStore`.
    public func refreshTemplates() async {
        let list = await TemplateStore.shared.templates()
        availableTemplates = list
    }

    /// Applies a template directory change: updates `TemplateStore` and refreshes the list.
    /// Pass `nil` to revert to the default Application Support path.
    public func applyTemplateDirectory(_ url: URL?) async {
        let resolved = url ?? TemplateStore.defaultDirectoryURL()
        await TemplateStore.shared.setDirectory(resolved)
        await refreshTemplates()
    }

    /// Opens a template: reads its content, then either triggers the placeholder sheet
    /// (if placeholders exist) or opens the document directly via `onOpenDocument`.
    public func openTemplate(record: TemplateRecord) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await TemplateStore.shared.rawContent(of: record)
                let keys = TemplatePlaceholderExpander.placeholders(in: content)
                if keys.isEmpty {
                    onOpenDocument?(content, record.fileExtension)
                } else {
                    templatePendingRequest = TemplatePendingRequest(
                        record: record, rawContent: content)
                }
            } catch {
                templateError =
                    error as? SputnikAlert
                    ?? .custom(title: "Template Error", message: error.localizedDescription)
            }
        }
    }

    /// Saves the provided content as a new template file and refreshes the list.
    ///
    /// - Throws: `SputnikAlert` when the file cannot be written or the name collides.
    public func saveCurrentAsTemplate(name: String, content: String, fileExtension: String)
        async throws
    {
        try await TemplateStore.shared.save(
            name: name, content: content, fileExtension: fileExtension)
        await refreshTemplates()
    }

    /// Moves a template file to the Trash and refreshes the list.
    ///
    /// - Throws: `SputnikAlert` when the trash operation fails.
    public func deleteTemplate(record: TemplateRecord) async throws {
        try await TemplateStore.shared.delete(record: record)
        await refreshTemplates()
    }
}
