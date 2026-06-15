import AppKit
import Foundation
import FoundationModule

/// Validates `.json` document text in real time and surfaces structural errors.
///
/// Gated by `EditorViewModel.jsonModeActive` and `SettingsStore.jsonValidationEnabled`.
/// Parsing runs on `Task(priority: .utility)` — never blocks the main thread (SR-4).
/// Errors are reported back to `EditorViewModel` as `validationErrors` (SR-1 — the
/// view model owns display state; this type owns only the parse logic).
@MainActor
public final class JSONValidator {

    // MARK: - Error model

    /// A single structural error located within the JSON document.
    public struct JSONError: Sendable {
        /// Human-readable description from `JSONSerialization`.
        public let message: String
        /// Approximate character offset, extracted from the error's `userInfo` when available.
        public let characterOffset: Int?
    }

    // MARK: - Dependencies

    private weak var viewModel: EditorViewModel?
    private let settings: SettingsStore
    private var validationTask: Task<Void, Never>?

    public init(viewModel: EditorViewModel, settings: SettingsStore) {
        self.viewModel = viewModel
        self.settings = settings
    }

    // MARK: - Public interface

    /// Validates `text` asynchronously. Call on every text change in `.json` mode.
    ///
    /// Debounced via the caller (EditorView's Coordinator); each call cancels the
    /// previous validation task before scheduling a new one.
    public func validate(text: String) {
        guard viewModel?.jsonModeActive == true,
            settings.jsonValidationEnabled
        else {
            viewModel?.jsonValidationErrors = []
            return
        }

        validationTask?.cancel()
        validationTask = Task { [weak self] in
            guard let self else { return }
            let errors = await Self.parse(text: text)
            guard !Task.isCancelled else { return }
            viewModel?.jsonValidationErrors = errors
        }
    }

    // MARK: - Parse (runs off main actor)

    /// Parses `text` and returns any `JSONError`s found.
    private static func parse(text: String) async -> [JSONError] {
        return await Task.detached(priority: .utility) {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
            guard let data = text.data(using: .utf8) else { return [] }
            do {
                _ = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
                return []
            } catch let error as NSError {
                let message = error.userInfo[NSDebugDescriptionErrorKey] as? String
                    ?? error.localizedDescription
                // Extract character offset from the debug description when present.
                // JSONSerialization embeds "around character N" in the description.
                let offset = Self.extractOffset(from: message)
                return [JSONError(message: message, characterOffset: offset)]
            }
        }.value
    }

    /// Extracts a character offset from a JSONSerialization error message.
    /// Looks for the pattern "around character N" (N is a decimal integer).
    private nonisolated static func extractOffset(from message: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "around character (\\d+)", options: [])
        else { return nil }
        let ns = message as NSString
        guard
            let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)),
            match.numberOfRanges > 1
        else { return nil }
        let digits = ns.substring(with: match.range(at: 1))
        return Int(digits)
    }
}
