import AppKit
import Foundation
import FoundationModule
import Observation

enum JSONViewerError: Error {
    case message(String)
}

/// View-model for the JSON Viewer panel.
///
/// Accepts raw JSON text from `DocumentSession`, pretty-prints it on a background
/// `Task(priority: .utility)`, and builds a syntax-coloured `NSAttributedString` using
/// the same colour scheme as `SyntaxHighlighter.jsonAttributes()`.
///
/// Rendering is debounced via `RenderThrottle` (Foundation 2.7) so rapid edits from
/// the paired editor don't cause redundant parses (SR-4).
///
/// Threading: all properties are written on `@MainActor`; the serialization work runs
/// detached at `.utility` priority and hops back before writing `renderedContent`.
@MainActor
@Observable
public final class JSONViewerViewModel {

    // MARK: - Output

    /// The most-recently rendered attributed string. `nil` while the first render is pending.
    public private(set) var renderedContent: NSAttributedString?

    /// Non-nil when the last parse attempt failed.
    public private(set) var lastError: String?

    /// The NSScrollView that owns the rendered text view. Wired in by the JSON viewer.
    /// Used by the minimap binder to observe scroll position.
    public var scrollView: NSScrollView?

    /// Whether `rawText` is currently empty.
    public var isEmpty: Bool { rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: - Input

    /// The raw JSON text to render. Set by `HTMLPreviewPanel` whenever the session updates.
    public var rawText: String = "" {
        didSet { scheduleRender() }
    }

    // MARK: - State

    public enum DisplayMode { case pretty, minified }
    public private(set) var displayMode: DisplayMode = .pretty

    // MARK: - Private

    private var renderTask: Task<Void, Never>?

    // MARK: - Public interface

    /// Toggles between pretty-printed and minified JSON and re-renders.
    public func toggleDisplayMode() {
        displayMode = (displayMode == .pretty) ? .minified : .pretty
        scheduleRender()
    }

    /// Rebuilds `renderedContent` from the current `rawText`.
    public func reload() {
        scheduleRender()
    }

    // MARK: - Rendering

    private func scheduleRender() {
        renderTask?.cancel()
        let text = rawText
        let mode = displayMode
        renderTask = Task { [weak self] in
            guard let self else { return }
            let result = await Self.render(text: text, mode: mode)
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let attributed):
                self.renderedContent = attributed
                self.lastError = nil
            case .failure(let error):
                if case .message(let message) = error {
                    self.lastError = message
                }
            }
        }
    }

    /// Parses and formats `text` off the main actor, returning a coloured attributed string.
    nonisolated private static func render(
        text: String,
        mode: DisplayMode
    ) async -> Result<NSAttributedString, JSONViewerError> {
        return await Task.detached(priority: .utility) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .success(NSAttributedString())
            }
            guard let data = trimmed.data(using: .utf8) else {
                return .failure(.message("Could not encode text as UTF-8."))
            }

            let jsonObject: Any
            do {
                jsonObject = try JSONSerialization.jsonObject(
                    with: data, options: .fragmentsAllowed)
            } catch {
                return .failure(.message(error.localizedDescription))
            }

            let outputData: Data
            do {
                let opts: JSONSerialization.WritingOptions =
                    (mode == .pretty)
                    ? [.prettyPrinted, .sortedKeys]
                    : []
                outputData = try JSONSerialization.data(withJSONObject: jsonObject, options: opts)
            } catch {
                return .failure(.message("Could not format JSON: \(error.localizedDescription)"))
            }

            guard let formatted = String(data: outputData, encoding: .utf8) else {
                return .failure(.message("UTF-8 decode failed after formatting."))
            }

            let attributed = Self.colorize(formatted)
            return .success(attributed)
        }.value
    }

    /// Applies the same colour scheme as `SyntaxHighlighter.jsonAttributes()`.
    ///
    /// Token colours:
    /// - Keys (strings before `:`): `.systemBlue`
    /// - String values (strings not before `:`): `.systemGreen`
    /// - Numbers: `.systemOrange`
    /// - Keywords `true`, `false`, `null`: `.systemPurple`
    nonisolated private static func colorize(_ text: String) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ])
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        // 1. Quoted strings — classify as key or value.
        let stringPattern = "\"(?:[^\"\\\\]|\\\\.)*\""
        if let stringRegex = try? NSRegularExpression(pattern: stringPattern) {
            for match in stringRegex.matches(in: text, range: fullRange) {
                let afterEnd = match.range.upperBound
                var nextNonSpace = afterEnd
                while nextNonSpace < ns.length {
                    let ch = ns.character(at: nextNonSpace)
                    if ch == 32 || ch == 9 || ch == 10 || ch == 13 {  // space, tab, newline, carriage return
                        nextNonSpace += 1
                    } else {
                        break
                    }
                }
                let isKey =
                    nextNonSpace < ns.length
                    && ns.character(at: nextNonSpace) == 58  // colon
                result.addAttribute(
                    .foregroundColor,
                    value: isKey ? NSColor.systemBlue : NSColor.systemGreen,
                    range: match.range)
            }
        }

        // 2. Numbers.
        let numberPattern = "-?\\b\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?\\b"
        if let numRegex = try? NSRegularExpression(pattern: numberPattern) {
            for match in numRegex.matches(in: text, range: fullRange) {
                result.addAttribute(
                    .foregroundColor, value: NSColor.systemOrange, range: match.range)
            }
        }

        // 3. Keywords.
        let keywordPattern = "\\b(?:true|false|null)\\b"
        if let kwRegex = try? NSRegularExpression(pattern: keywordPattern) {
            for match in kwRegex.matches(in: text, range: fullRange) {
                result.addAttribute(
                    .foregroundColor, value: NSColor.systemPurple, range: match.range)
            }
        }

        return result
    }
}
