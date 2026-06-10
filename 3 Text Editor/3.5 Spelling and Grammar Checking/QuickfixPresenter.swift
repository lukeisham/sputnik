import AppKit
import FoundationModule

/// Presents an `NSMenu` of spelling corrections on right-click over an underlined range.
///
/// Applies the chosen correction via `NSTextStorage.replaceCharacters(in:with:)`.
/// AppKit requires `NSSpellChecker` and all `NSTextStorage` mutations on `@MainActor`.
@MainActor
public final class QuickfixPresenter {

    // MARK: - Dependencies

    private weak var textView: NSTextView?
    private let spellDocumentTag: Int
    private let settings: SettingsStore

    public init(textView: NSTextView, spellDocumentTag: Int, settings: SettingsStore) {
        self.textView = textView
        self.spellDocumentTag = spellDocumentTag
        self.settings = settings
    }

    // MARK: - Public interface

    /// Builds and returns a corrections menu for the right-click event.
    ///
    /// Call from `NSTextView.menu(for:)` or the right-click responder.
    ///
    /// - Parameters:
    ///   - event:     The right-click `NSEvent`.
    ///   - wordRange: The underlined range under the click.
    /// - Returns: A populated `NSMenu`, or `nil` if no corrections are available.
    public func menu(for event: NSEvent, wordRange range: NSRange) -> NSMenu? {
        guard let textView, let storage = textView.textStorage else { return nil }

        let candidates =
            NSSpellChecker.shared.guesses(
                forWordRange: range,
                in: storage.string,
                language: settings.spellCheckLocale,
                inSpellDocumentWithTag: spellDocumentTag
            ) ?? []

        guard !candidates.isEmpty else { return nil }

        let menu = NSMenu(title: "Spelling")
        for candidate in candidates.prefix(8) {
            let item = NSMenuItem(
                title: candidate,
                action: #selector(applyCorrection(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NSValue(range: range)
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Private

    @objc private func applyCorrection(_ sender: NSMenuItem) {
        guard
            let textView,
            let storage = textView.textStorage,
            let rangeValue = sender.representedObject as? NSValue
        else { return }

        let range = rangeValue.rangeValue
        let word = sender.title

        // No-op if the range became stale after a concurrent edit (guide failure mode).
        guard range.location != NSNotFound,
            range.location + range.length <= storage.length
        else { return }

        storage.replaceCharacters(in: range, with: word)
    }
}
