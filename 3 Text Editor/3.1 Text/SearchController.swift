import AppKit
import Observation

/// Manages find/replace state and match highlighting in the editor's `NSTextStorage`.
///
/// Spec 3.1.5. Keeping match-state logic here and presentation in `SearchBarView`
/// respects SR-6 (one responsibility per file). The search bar is SwiftUI; this
/// controller is the only file that touches `NSTextStorage` for highlight ranges.
@Observable
@MainActor
public final class SearchController {

    // MARK: - State

    /// Whether the find/replace bar is currently visible.
    public var isVisible: Bool = false

    /// Current search term.
    public var searchTerm: String = ""

    /// Current replacement term.
    public var replaceTerm: String = ""

    /// Index into `matchRanges` for the currently selected result.
    public var currentMatchIndex: Int = 0

    /// All match ranges in the document for the current `searchTerm`.
    public private(set) var matchRanges: [NSRange] = []

    // MARK: - Private

    private weak var textView: NSTextView?

    public init(textView: NSTextView) {
        self.textView = textView
    }

    // MARK: - Actions

    /// Toggles the find bar visibility. Clears highlights when hiding.
    public func toggleVisible() {
        isVisible.toggle()
        if !isVisible { clearHighlights() }
    }

    /// Runs a case-insensitive search and highlights all matches.
    public func search() {
        guard let textView, let storage = textView.textStorage else { return }
        clearHighlights()
        guard !searchTerm.isEmpty else { return }

        let text = storage.string as NSString
        var found = [NSRange]()
        var pos   = 0

        while pos < text.length {
            let remaining = NSRange(location: pos, length: text.length - pos)
            let match     = text.range(of: searchTerm, options: .caseInsensitive, range: remaining)
            if match.location == NSNotFound { break }
            found.append(match)
            pos = match.location + max(1, match.length)  // advance at least 1 to avoid infinite loop
        }

        matchRanges       = found
        currentMatchIndex = 0
        applyHighlights()
    }

    /// Advances to the next match (wraps around).
    public func nextMatch() {
        guard !matchRanges.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchRanges.count
        scrollToCurrentMatch()
    }

    /// Goes back to the previous match (wraps around).
    public func previousMatch() {
        guard !matchRanges.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matchRanges.count) % matchRanges.count
        scrollToCurrentMatch()
    }

    /// Replaces the current match with `replaceTerm`, then re-searches.
    public func replaceCurrent() {
        guard !matchRanges.isEmpty,
              let textView,
              let storage = textView.textStorage else { return }
        let range = matchRanges[currentMatchIndex]
        guard range.location + range.length <= storage.length else { return }
        storage.replaceCharacters(in: range, with: replaceTerm)
        search()
    }

    /// Replaces all matches. Applies in reverse so earlier ranges stay valid.
    public func replaceAll() {
        guard let textView, let storage = textView.textStorage else { return }
        search()
        for range in matchRanges.reversed() {
            guard range.location + range.length <= storage.length else { continue }
            storage.replaceCharacters(in: range, with: replaceTerm)
        }
        clearHighlights()
    }

    // MARK: - Private helpers

    private func applyHighlights() {
        guard let textView, let storage = textView.textStorage else { return }
        storage.beginEditing()
        for (i, range) in matchRanges.enumerated() {
            guard range.location + range.length <= storage.length else { continue }
            let color: NSColor = i == currentMatchIndex ? .systemOrange : .systemYellow
            storage.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.35), range: range)
        }
        storage.endEditing()
        scrollToCurrentMatch()
    }

    private func clearHighlights() {
        guard let textView, let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.backgroundColor, range: full)
        storage.endEditing()
        matchRanges = []
    }

    private func scrollToCurrentMatch() {
        guard !matchRanges.isEmpty, let textView else { return }
        let range = matchRanges[currentMatchIndex]
        textView.scrollRangeToVisible(range)
        textView.setSelectedRange(range)
    }
}
