import AppKit

/// Encodes the **Interaction-replaces-More-Context** precedence rule in one place,
/// so all three hosts (Text Editor, Markdown Preview, HTML Preview) behave identically (SR-1).
///
/// When a special element is detected at the selection and Interaction is enabled for
/// that language, returns a single "Interact with…" item **instead of** More-Context items.
/// Otherwise returns the unchanged More-Context items.
@MainActor
public enum SelectionContextMenu {

    /// Builds context menu items respecting the Interaction-vs-More-Context precedence.
    ///
    /// - Parameters:
    ///   - selectedText: The user's selected text. Returns `[]` when empty.
    ///   - fullText: The full document text.
    ///   - cursorOffset: UTF-16 offset of the cursor/selection start.
    ///   - selectionLength: Length of the selection in UTF-16 units.
    ///   - mode: The active editor mode.
    ///   - detector: The `SpecialElementDetecting` instance (module 9, via protocol).
    ///   - interactionEnabled: Whether Interaction is toggled on for this mode's language.
    ///   - moreContextKinds: The `HelpTopic` kinds for More-Context items.
    ///   - resolver: The `HelpContextResolving` instance for More-Context.
    ///   - onInteract: Called when the "Interact with…" item is chosen, with the detected element.
    ///   - onMoreContext: Called when a More-Context item is chosen.
    /// - Returns: Menu items — either a single "Interact with…" item or the More-Context items.
    public static func items(
        forSelectedText selectedText: String,
        fullText: String,
        cursorOffset: Int,
        selectionLength: Int,
        language: WritingAssistLanguage,
        detector: SpecialElementDetecting,
        interactionEnabled: Bool,
        moreContextKinds: [HelpTopic],
        resolver: HelpContextResolving,
        onInteract: @escaping (SpecialElement) -> Void,
        onMoreContext: @escaping (HelpRequest?) -> Void
    ) -> [NSMenuItem] {
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let selectedRange = NSRange(location: cursorOffset, length: selectionLength)

        // Attempt to detect a special element.
        if interactionEnabled,
            let element = detector.detect(
                in: fullText, selectedRange: selectedRange, language: language)
        {
            // Interaction takes precedence — return a single "Interact with…" item.
            let item = ClosureMenuItem(title: "Interact with \"\(element.syntaxTerm)\"") {
                onInteract(element)
            }
            return [item]
        }

        // No special element detected or Interaction disabled — fall through to More-Context.
        return MoreContextMenu.items(
            forSelectedText: selectedText,
            kinds: moreContextKinds,
            fullText: fullText,
            cursorOffset: cursorOffset,
            selectionLength: selectionLength,
            resolver: resolver,
            onRequest: onMoreContext
        )
    }
}
