import AppKit

/// A shared builder that creates "More Context: …" menu items for any text-display
/// panel in Sputnik.
///
/// This is the shared gesture plumbing (SR-1: Foundation owns plumbing, not orchestration).
/// Hosts call `items(forSelectedText:kinds:fullText:cursorOffset:resolver:onRequest:)`
/// and insert the result into their context menu. The host supplies its candidate help
/// kinds, the selected text, and an `onRequest` sink that writes the resulting
/// `HelpRequest` to `AppState.requestedHelpTarget`.
///
/// **Usage (in any NSView/NSViewController menu override):**
/// ```swift
/// let moreItems = MoreContextMenu.items(
///     forSelectedText: selected,
///     kinds: [.grammar, .markdown],
///     fullText: fullText,
///     cursorOffset: cursorOffset,
///     resolver: resolver,
///     onRequest: { [weak appState] request in appState?.requestedHelpTarget = request }
/// )
/// moreItems.forEach { menu.insertItem($0, at: 0) }
/// ```
@MainActor
public enum MoreContextMenu {

    /// Builds "More Context: <kind.title>" menu items for each candidate help kind.
    ///
    /// Each item, when activated, resolves the selection through the shared resolver and
    /// routes the result through the `onRequest` sink (which should write to
    /// `AppState.requestedHelpTarget`).
    ///
    /// - Parameters:
    ///   - selectedText: The text currently selected by the user. Returns `[]` when empty
    ///     or whitespace-only.
    ///   - kinds: The candidate `HelpTopic` kinds to build items for. One item per kind.
    ///   - fullText: The full text of the document or view content.
    ///   - cursorOffset: The UTF-16 offset of the cursor or selection start.
    ///   - selectionLength: The length of the selection in UTF-16 units (default 0).
    ///   - resolver: The shared `HelpContextResolving` instance (concrete type from module 9).
    ///   - onRequest: A closure receiving the resolved `HelpRequest` (or `nil`). The host
    ///     writes this to `AppState.requestedHelpTarget`.
    /// - Returns: An array of `NSMenuItem` instances. Empty when `selectedText` is empty
    ///   or whitespace-only.
    public static func items(
        forSelectedText selectedText: String,
        kinds: [HelpTopic],
        fullText: String,
        cursorOffset: Int,
        selectionLength: Int = 0,
        resolver: HelpContextResolving,
        onRequest: @escaping (HelpRequest?) -> Void
    ) -> [NSMenuItem] {
        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return kinds.map { kind in
            ClosureMenuItem(title: "More Context: \(kind.title)") {
                let query = HelpContextQuery(
                    kind: kind,
                    selectedText: selectedText,
                    fullText: fullText,
                    cursorOffset: cursorOffset,
                    selectionLength: selectionLength
                )
                Task {
                    let request = await resolver.resolve(query)
                    onRequest(request)
                }
            }
        }
    }
}
