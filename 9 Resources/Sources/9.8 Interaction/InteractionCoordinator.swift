import AppKit
import Foundation
import FoundationModule

/// Orchestrates the full Interaction flow: detect → resolve → auto-fill (or fallback popup).
///
/// Holds references to the provider, inserter, and settings. Hosts (Text Editor, Markdown
/// Preview, HTML Preview) hold one shared coordinator.
@MainActor
public final class InteractionCoordinator {

    // MARK: - Properties

    /// The special element detector, exposed for host modules to pass to `SelectionContextMenu`.
    public let detector: SpecialElementDetector
    private let provider: InteractionProvider
    private let inserter: ContentInserter
    private let registry: SpecialElementRegistry
    private weak var settingsStore: SettingsStore?

    /// The last detected element, updated on selection-change.
    public private(set) var detectedElement: SpecialElement?

    /// `true` when a special element is detected and Interaction is enabled for the mode.
    public private(set) var isAvailable: Bool = false

    /// Called when `isAvailable` changes, so the host can update UI.
    public var onAvailabilityChanged: ((Bool) -> Void)?

    // MARK: - Init

    public init(
        detector: SpecialElementDetector? = nil,
        provider: InteractionProvider? = nil,
        inserter: ContentInserter? = nil,
        registry: SpecialElementRegistry = .shared,
        settingsStore: SettingsStore? = nil
    ) {
        self.detector = detector ?? SpecialElementDetector()
        self.provider = provider ?? InteractionProvider()
        self.inserter = inserter ?? ContentInserter()
        self.registry = registry
        self.settingsStore = settingsStore
    }

    // MARK: - Detection

    /// Called on selection-change to update the detected element and availability.
    /// - Parameters:
    ///   - text: The full document text.
    ///   - selectedRange: The current selection NSRange.
    ///   - language: The resource/writing-assist language for the active mode.
    public func updateDetection(
        text: String, selectedRange: NSRange, language: WritingAssistLanguage
    ) {
        guard settingsStore?.writingAssist.isEnabled(.interaction, for: language) == true
        else {
            detectedElement = nil
            isAvailable = false
            onAvailabilityChanged?(false)
            return
        }

        // Run detection synchronously on MainActor.
        guard
            let element = detector.detect(
                in: text, selectedRange: selectedRange, language: language)
        else {
            detectedElement = nil
            isAvailable = false
            onAvailabilityChanged?(false)
            return
        }

        // Resolve definitionID from the registry (async, but we fire-and-forget
        // and store the resolved element).
        detectedElement = element
        isAvailable = true
        onAvailabilityChanged?(true)

        // Asynchronously resolve the definitionID and update.
        Task { [weak self] in
            guard let self else { return }
            if let resolved = await self.detector.resolveDefinition(for: element) {
                self.detectedElement = resolved
            }
        }
    }

    // MARK: - Trigger (called from Edit menu ⌘I or right-click)

    /// Triggers the interaction: builds a query, calls the provider, and auto-fills
    /// (or shows a popup for the fuzzy fallback / ambiguous slots).
    /// - Parameters:
    ///   - rect: The anchor rect for any popup (in `view` coordinates).
    ///   - view: The view to present popups from.
    ///   - selectedText: The user's selected text.
    ///   - fullText: The full document text.
    ///   - language: The resource/writing-assist language.
    ///   - onInsert: Called with the text to insert and the NSRange to replace.
    public func trigger(
        relativeTo rect: NSRect,
        in view: NSView,
        selectedText: String,
        fullText: String,
        language: WritingAssistLanguage,
        onInsert: @escaping (String, NSRange) -> Void
    ) {
        guard let element = detectedElement else { return }

        let query = InteractionQuery(
            selectedText: selectedText,
            fullText: fullText,
            cursorOffset: element.selectedLineRange.location,
            selectionLength: selectedText.utf16.count,
            fileLanguage: language,
            detectedElement: element
        )

        Task { [weak self] in
            guard let self else { return }
            let result = await self.provider.sections(for: query)

            if result.sections.isEmpty {
                // No content to insert — show a brief message.
                InteractionPopupMenu.present(
                    title: "No relevant content found",
                    items: [],
                    relativeTo: rect,
                    in: view,
                    onSelect: { _ in }
                )
                return
            }

            // Primary path: registered element with auto-fill (no popup).
            if element.definitionID != nil {
                let (newText, range) = self.inserter.insertTemplate(
                    result, into: element, fullText: fullText)
                onInsert(newText, range)
                return
            }

            // Fallback path: show popup for the user to pick.
            InteractionPopupMenu.present(
                title: result.insertionDescription,
                items: result.sections,
                relativeTo: rect,
                in: view
            ) { [weak self] selectedItem in
                guard let self else { return }
                let (newText, range) = self.inserter.insert(
                    selectedItem, into: element, fullText: fullText)
                onInsert(newText, range)
            }
        }
    }

    // MARK: - Helpers
}
