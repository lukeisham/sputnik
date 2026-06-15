import AppKit
import FoundationModule

/// Generates JSON key and value completions at the cursor using ghost text.
///
/// Only active when `EditorViewModel.jsonModeActive` is `true` and
/// `SettingsStore.jsonAutoCompleteEnabled` is `true`.
/// Debounced via Foundation 2.7 `DebounceTimer`.
/// Renders through the shared `GhostTextOverlay` from 3.1.
@MainActor
public final class JSONLanguageProvider {

    // MARK: - Dependencies

    private weak var textView: NSTextView?
    private weak var ghostOverlay: GhostTextOverlay?
    private weak var viewModel: EditorViewModel?
    private let settings: SettingsStore
    private let debounce = DebounceTimer()

    public init(
        textView: NSTextView,
        ghostOverlay: GhostTextOverlay,
        viewModel: EditorViewModel,
        settings: SettingsStore
    ) {
        self.textView = textView
        self.ghostOverlay = ghostOverlay
        self.viewModel = viewModel
        self.settings = settings
    }

    // MARK: - Public interface

    /// Call on every keypress in `.json` mode.
    public func onKeypress() {
        guard viewModel?.jsonModeActive == true,
            settings.jsonAutoCompleteEnabled
        else {
            ghostOverlay?.clear()
            return
        }
        debounce.schedule(delay: settings.jsonAutoCompleteStep.timeInterval) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.generateSuggestion()
            }
        }
    }

    // MARK: - Suggestion generation

    private func generateSuggestion() async {
        guard let textView,
            let storage = textView.textStorage
        else { return }

        let cursorLocation = textView.selectedRange().location
        let text = storage.string
        let ns = text as NSString
        let safeLocation = min(cursorLocation, ns.length)

        // Determine context: what is the character immediately before the cursor?
        let precedingText = ns.substring(to: safeLocation)
        let suggestion = await Task.detached(priority: .utility) {
            Self.suggest(in: precedingText)
        }.value

        guard let suggestion else {
            ghostOverlay?.clear()
            return
        }
        ghostOverlay?.show(suggestion)
    }

    /// Analyses the text before the cursor to produce a completion string.
    /// Returns `nil` when no sensible completion is available.
    /// `internal` (not `private`) so tests can call it directly without a shim.
    nonisolated static func suggest(in precedingText: String) -> String? {
        let trimmed = precedingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let last = trimmed.last

        // After an opening brace with nothing yet → suggest a key template.
        if last == "{" { return "\"key\": " }

        // After a colon with optional space → suggest empty string value.
        if last == ":" { return " \"\"" }

        // After a comma or opening bracket → next element.
        if last == "," { return " " }
        if last == "[" { return "\"\"" }

        return nil
    }
}
