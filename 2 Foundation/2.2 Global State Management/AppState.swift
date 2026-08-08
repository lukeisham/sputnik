import AppKit
import Foundation
import Observation

/// Coordinator for all open windows. Owns the collection of `WindowState` instances
/// and provides computed pass-through accessors that delegate to the active window,
/// so existing callers written against the single-window model continue to compile.
///
/// **Multi-window model:**
/// - One `WindowState` per open window. Created via `createWindow()`.
/// - `activeWindowID` tracks the frontmost window, updated via `setActiveWindow(_:)`.
/// - All "current document / layout" reads delegate to `activeWindow`.
///
/// **File organization (SR-6):** `AppState` is split across focused extension files in
/// this directory (`AppState+WindowRegistry.swift`, `AppState+DocumentLifecycle.swift`,
/// etc.). Stored properties and `init` live here because Swift forbids stored properties
/// in extensions. Template state is owned by `templateManager`; the template members on
/// `AppState` are thin pass-throughs kept for caller compatibility (see Step 4 of the
/// SR-6 plan for the eventual migration).
///
/// **Threading:** `@MainActor` — all reads and writes happen on the main thread.
///
/// **Sendable:** This class does not conform to `Sendable`. It is `@MainActor`-isolated,
/// so all property access is confined to the main actor. Callers that need to read
/// `AppState` from outside the main actor must use `Task { @MainActor in … }` or
/// explicitly isolate themselves. Do **not** add `@unchecked Sendable` — it would
/// suppress data-race detection without providing any safety benefit.
@Observable
@MainActor
public final class AppState {

    // MARK: - Window registry (stored)

    /// Ordered list of window IDs (insertion order = creation order).
    /// Mutated by the window-lifecycle methods in `AppState+WindowRegistry.swift` and the
    /// restore logic in `AppState+WindowPersistence.swift`, hence `internal(set)`.
    public internal(set) var orderedWindowIDs: [UUID] = []

    /// All open windows, keyed by their stable UUID.
    public internal(set) var windows: [UUID: WindowState] = [:]

    /// The UUID of the currently frontmost window. Updated by `setActiveWindow(_:)`
    /// when the key window changes (via `@FocusedValue` or `NSApp.keyWindow` observation).
    public var activeWindowID: UUID?

    // MARK: - Interaction state (stored)

    /// `true` when a special element is detected at the current selection and Interaction
    /// is enabled for the active editor mode. Observed by the Edit menu "Interact with" item.
    public var isInteractionAvailable: Bool = false

    // MARK: - AI state (stored — Supporting AI is app-level; Main AI is per-window)

    /// Cumulative Supporting AI token usage for the current session.
    public var supportingAIUsage: SupportingAIUsage?

    // MARK: - Editor command handler (stored, SR-1)

    /// The registered editor command handler (Save, Save As, Render as HTML, ASCII Studio).
    /// Set by the text editor module at launch via `registerEditorCommandHandler(_:)`
    /// (defined in `AppState+CommandRouting.swift`), hence `internal(set)`.
    public internal(set) var editorCommandHandler: EditorCommandHandling?

    // MARK: - Paired preview actions (stored, SR-1)

    /// Print closure supplied by the active Markdown or HTML preview panel.
    /// Non-nil only while a preview panel is open and rendering the active document.
    /// Cleared by the panel on document type mismatch, disappearance, or document switch.
    public var pairedPreviewPrintAction: (() -> Void)?

    /// Save-as-PDF closure supplied by the active Markdown or HTML preview panel.
    /// Non-nil only while a preview panel is open and rendering the active document.
    /// Cleared by the panel on document type mismatch, disappearance, or document switch.
    public var pairedPreviewSaveAsPDFAction: (() -> Void)?

    /// The inter-panel router used by the editor to open files in other panels.
    /// Set by the app at launch; required for Render as HTML and other routing operations.
    public weak var router: (any InterPanelRouter)?

    // MARK: - Crash recovery (stored, ISS-108)

    /// Names of crash-recovery files awaiting user action. Set at launch by AppDelegate;
    /// cleared when the user accepts or dismisses each entry.
    public var pendingRecoveryNames: [String] = []

    // MARK: - Multi-window persistence (stored, step 9)

    /// Window IDs that still need their SwiftUI scene opened after launch.
    /// Populated during `restoreWindows(from:)` for all windows beyond the first,
    /// which is already handled by the initial `WindowGroup` scene creation.
    public var pendingWindowIDs: [UUID] = []

    // MARK: - Templates (2.10)

    /// Owns all template state and async operations. The template members on `AppState`
    /// below are thin pass-throughs that delegate here.
    public let templateManager = TemplateManager()

    // MARK: - Init

    public init() {
        // Create the first window immediately so the app has a valid active window
        // before the first `ContentView` renders.
        let first = WindowState()
        windows[first.id] = first
        orderedWindowIDs.append(first.id)
        activeWindowID = first.id

        // Route template-document creation back through the window-aware path.
        templateManager.onOpenDocument = { [weak self] content, ext in
            self?.openTemplateDocument(content: content, fileExtension: ext)
        }
    }

    // MARK: - Template management (delegates to templateManager)

    /// The list of available templates in the current template directory.
    public var availableTemplates: [TemplateRecord] {
        templateManager.availableTemplates
    }

    /// Non-nil when the user has selected a template that contains placeholders.
    public var templatePendingRequest: TemplatePendingRequest? {
        get { templateManager.templatePendingRequest }
        set { templateManager.templatePendingRequest = newValue }
    }

    /// Non-nil when a template operation fails; drives an alert in `ContentView`.
    public var templateError: SputnikAlert? {
        get { templateManager.templateError }
        set { templateManager.templateError = newValue }
    }

    /// Reloads `availableTemplates` from `TemplateStore`.
    public func refreshTemplates() async {
        await templateManager.refreshTemplates()
    }

    /// Applies a template directory change. Pass `nil` to revert to the default path.
    public func applyTemplateDirectory(_ url: URL?) async {
        await templateManager.applyTemplateDirectory(url)
    }

    /// Opens a template: either triggers the placeholder sheet or opens the document.
    public func openTemplate(record: TemplateRecord) {
        templateManager.openTemplate(record: record)
    }

    /// Creates a new untitled `DocumentSession` pre-loaded with the expanded template content.
    /// Stays on `AppState` because it directly manipulates `activeWindow.openDocuments`;
    /// wired as `templateManager.onOpenDocument` in `init`.
    public func openTemplateDocument(content: String, fileExtension: String) {
        let fileType = FileType(extension: fileExtension)
        guard let win = activeWindow else { return }
        let session = DocumentSession(url: nil, fileType: fileType, text: content, isDirty: true)
        win.openDocuments.append(session)
        win.activeDocumentID = session.id
    }

    /// Reads the active document's content and saves it as a new template file.
    ///
    /// - Throws: `SputnikAlert` when the file cannot be written or the name collides.
    public func saveCurrentAsTemplate(name: String) async throws {
        guard let content = activeDocument?.text else { return }
        let ext = activeDocument?.fileType.defaultExtension ?? "txt"
        try await templateManager.saveCurrentAsTemplate(
            name: name, content: content, fileExtension: ext)
    }

    /// Moves a template file to the Trash and refreshes the list.
    ///
    /// - Throws: `SputnikAlert` when the trash operation fails.
    public func deleteTemplate(record: TemplateRecord) async throws {
        try await templateManager.deleteTemplate(record: record)
    }
}
