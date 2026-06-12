import AppKit
import FoundationModule
import SputnikShared

/// Lightweight, real-time HTML structural checker.
///
/// A deliberately small clone of `SpellingGrammarChecker`'s pipeline — debounce → scan →
/// annotate → underline → hit-test — but with the `NSSpellChecker` call replaced by a
/// regex-based structural scan. It catches the common, high-signal mistakes (unclosed and
/// mismatched tags, unquoted attribute values broken by a space, duplicate `id`s) without
/// a full HTML5 parser.
///
/// Like the spelling checker, it writes `.underlineStyle` / `.underlineColor` attributes
/// directly to `NSTextStorage` and keeps a parallel `GrammarAnnotation` model the editor can
/// hit-test on click. HTML underlines are blue (`.systemBlue`) to distinguish them from
/// spelling (red) and grammar (orange).
///
/// Only active when `EditorViewModel.htmlModeActive` is `true` **and**
/// `SettingsStore.htmlSyntaxCheckEnabled` is `true`. The structural scan runs on a
/// `.utility` task off the main thread (SR-4); only the attribute writes touch `@MainActor`.
@MainActor
public final class HTMLSyntaxChecker {

    // MARK: - Dependencies

    private weak var textView: NSTextView?
    private weak var viewModel: EditorViewModel?
    /// Read-only query of the spelling checker's current issues, so HTML underlines that
    /// overlap a spelling underline can be suppressed (spelling takes priority, invariant 4).
    private weak var spellingChecker: SpellingGrammarChecker?
    private let settings: SettingsStore
    private let debounce = DebounceTimer()

    // MARK: - Annotation model (hit-testable by the editor)

    /// The current HTML issues, including suppressed ones. Rebuilt on every check.
    /// Read-only to collaborators; the editor queries it via `annotation(at:)`.
    public private(set) var annotations: [GrammarAnnotation] = []

    /// Structural issues the user has dismissed this session (keyed by the underlined text).
    /// Re-checks exclude them. Session-only — not persisted.
    private var ignoredHTMLPhrases: Set<String> = []

    public init(
        textView: NSTextView,
        viewModel: EditorViewModel,
        settings: SettingsStore,
        spellingChecker: SpellingGrammarChecker? = nil
    ) {
        self.textView = textView
        self.viewModel = viewModel
        self.settings = settings
        self.spellingChecker = spellingChecker
    }

    // MARK: - Public interface

    /// Call on every `NSTextStorage` change. No-ops unless HTML mode is active and the
    /// feature is enabled in Settings.
    public func onTextChange() {
        guard isActive else {
            clearIfNeeded()
            return
        }
        debounce.schedule(delay: settings.htmlDebounceInterval) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.runCheck()
            }
        }
    }

    /// Runs the check immediately (no debounce). Used after a popover Fix/Dismiss.
    public func recheckNow() {
        Task { @MainActor [weak self] in
            await self?.runCheck()
        }
    }

    /// Returns the rendered (non-suppressed) annotation containing `location`, or `nil`.
    /// Reads the in-memory model only — no re-scan (SR-4).
    public func annotation(at location: Int) -> GrammarAnnotation? {
        annotations.first { !$0.isSuppressed && NSLocationInRange(location, $0.range) }
    }

    /// Dismisses an annotation for the rest of this session, then re-checks so the
    /// underline clears.
    public func dismiss(_ annotation: GrammarAnnotation) {
        guard let storage = textView?.textStorage else { return }
        let range = annotation.range
        // Guard against ranges invalidated by a concurrent edit (SR-2).
        guard range.location != NSNotFound,
            range.location + range.length <= storage.length
        else { return }
        let phrase = (storage.string as NSString).substring(with: range)
        ignoredHTMLPhrases.insert(phrase)
        recheckNow()
    }

    // MARK: - Activation

    private var isActive: Bool {
        viewModel?.htmlModeActive == true && settings.htmlSyntaxCheckEnabled
    }

    /// Clears any HTML underlines and the annotation model when the checker goes inactive
    /// (mode switched away, or the feature toggled off).
    private func clearIfNeeded() {
        guard !annotations.isEmpty else { return }
        annotations = []
        guard let storage = textView?.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.underlineStyle, range: full)
        storage.removeAttribute(.underlineColor, range: full)
        storage.endEditing()
    }

    // MARK: - Checking

    private func runCheck() async {
        guard isActive,
            let textView,
            let storage = textView.textStorage,
            storage.length > 0
        else {
            clearIfNeeded()
            return
        }

        let text = storage.string

        // Structural scan off the main thread (SR-4). Findings carry only value types.
        let findings = await Task(priority: .utility) {
            HTMLSyntaxChecker.scan(text)
        }.value

        // The buffer may have changed while we scanned — re-validate against current length.
        guard isActive, let storage = textView.textStorage else {
            clearIfNeeded()
            return
        }
        let length = storage.length
        let nsString = storage.string as NSString

        // Spelling annotations to defer to (spelling underline wins on overlap, invariant 4).
        let spellingRanges: [NSRange] =
            spellingChecker?.annotations
            .filter { $0.kind == .spelling && !$0.isSuppressed }
            .map { $0.range } ?? []

        var newAnnotations: [GrammarAnnotation] = []
        for finding in findings {
            let range = finding.range
            guard range.location != NSNotFound,
                range.location + range.length <= length
            else { continue }
            let phrase = nsString.substring(with: range)
            if ignoredHTMLPhrases.contains(phrase) { continue }
            let suppressed = spellingRanges.contains {
                NSIntersectionRange($0, range).length > 0
            }
            newAnnotations.append(
                GrammarAnnotation(
                    range: range,
                    kind: .htmlSyntax,
                    suggestions: [finding.message],
                    isSuppressed: suppressed
                )
            )
        }

        annotations = newAnnotations

        // Render: clear previous underlines, then draw only non-suppressed annotations.
        let full = NSRange(location: 0, length: length)
        storage.beginEditing()
        storage.removeAttribute(.underlineStyle, range: full)
        storage.removeAttribute(.underlineColor, range: full)
        for annotation in newAnnotations where !annotation.isSuppressed {
            storage.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: annotation.range)
            storage.addAttribute(.underlineColor, value: NSColor.systemBlue, range: annotation.range)
        }
        storage.endEditing()
    }

    // MARK: - Structural scan (pure, runs off-main)

    /// A single structural finding: the character range to underline and a human message.
    /// Value type so it can cross the `.utility` task boundary (Sendable).
    struct Finding: Sendable {
        let range: NSRange
        let message: String
    }

    /// Block-level elements that require a matching closing tag. Tracked on the tag stack.
    nonisolated private static let blockTags: Set<String> = [
        "div", "p", "span", "ul", "ol", "li", "table", "tr", "td", "th",
        "section", "article", "header", "footer", "nav", "main", "aside",
        "h1", "h2", "h3", "h4", "h5", "h6", "form", "fieldset", "body", "head", "html",
    ]

    /// Void elements that never take a closing tag — excluded from the stack.
    nonisolated private static let voidTags: Set<String> = [
        "br", "hr", "img", "input", "meta", "link", "area", "base",
        "col", "embed", "source", "track", "wbr",
    ]

    /// Boolean attributes that legitimately appear without a value — used to avoid false
    /// positives in the unquoted-attribute check (e.g. `<input type=text required>`).
    nonisolated private static let booleanAttributes: Set<String> = [
        "required", "disabled", "checked", "selected", "readonly", "multiple",
        "autofocus", "hidden", "async", "defer", "novalidate", "open", "ismap",
    ]

    /// Matches one HTML tag: optional leading `/`, a name, the (lazy) attribute body, and an
    /// optional trailing `/` for self-closing tags.
    nonisolated(unsafe) private static let tagRegex = try? NSRegularExpression(
        pattern: "</?([a-zA-Z][a-zA-Z0-9]*)((?:[^>\"']|\"[^\"]*\"|'[^']*')*?)(/?)>",
        options: [])

    /// Runs the three structural passes over `text` and returns findings in document order.
    /// `nonisolated` so it can run on a `.utility` task off the main thread (SR-4).
    nonisolated static func scan(_ text: String) -> [Finding] {
        guard let regex = tagRegex else { return [] }
        let nsString = text as NSString
        let full = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: text, options: [], range: full)

        var findings: [Finding] = []
        // Stack of unclosed opening tags: (lowercased name, tag range).
        var openStack: [(name: String, range: NSRange)] = []
        var seenIDs: Set<String> = []

        for match in matches {
            let tagRange = match.range
            let raw = nsString.substring(with: match.range(at: 1))
            let name = raw.lowercased()
            let attrs = match.range(at: 2).location != NSNotFound
                ? nsString.substring(with: match.range(at: 2)) : ""
            let selfClosed = match.range(at: 3).length > 0
            let isClosing = nsString.substring(with: tagRange).hasPrefix("</")

            if isClosing {
                guard blockTags.contains(name) else { continue }
                if openStack.last?.name == name {
                    openStack.removeLast()
                } else {
                    let expected = openStack.last.map { "</\($0.name)>" } ?? "no open tag"
                    findings.append(
                        Finding(
                            range: tagRange,
                            message: "Mismatched closing tag — expected \(expected)"))
                }
                continue
            }

            // Opening (or self-closing) tag: run attribute checks regardless of element type.
            checkAttributes(attrs: attrs, attrsRange: match.range(at: 2),
                nsString: nsString, seenIDs: &seenIDs, findings: &findings)

            // Only block tags that are not self-closed go on the stack.
            if !selfClosed, !voidTags.contains(name), blockTags.contains(name) {
                openStack.append((name: name, range: tagRange))
            }
        }

        // Anything left open at end of document is unclosed.
        for open in openStack {
            findings.append(
                Finding(range: open.range, message: "Unclosed <\(open.name)>"))
        }

        // Return in document order so the first issue underlines first.
        return findings.sorted { $0.range.location < $1.range.location }
    }

    /// Attribute-level passes for a single tag: unquoted values broken by a space, and
    /// duplicate `id` values across the document.
    nonisolated private static func checkAttributes(
        attrs: String,
        attrsRange: NSRange,
        nsString: NSString,
        seenIDs: inout Set<String>,
        findings: inout [Finding]
    ) {
        guard attrsRange.location != NSNotFound, !attrs.isEmpty else { return }
        let base = attrsRange.location
        let attrNS = attrs as NSString
        let attrFull = NSRange(location: 0, length: attrNS.length)

        // Duplicate id — match quoted `id="value"` (and unquoted `id=value`).
        if let idRegex = idRegex {
            for m in idRegex.matches(in: attrs, options: [], range: attrFull) {
                // Group 1 = double-quoted, 2 = single-quoted, 3 = unquoted.
                let valueRange =
                    [1, 2, 3].map { m.range(at: $0) }.first { $0.location != NSNotFound }
                    ?? NSRange(location: NSNotFound, length: 0)
                guard valueRange.location != NSNotFound else { continue }
                let value = attrNS.substring(with: valueRange)
                if seenIDs.contains(value) {
                    let abs = NSRange(location: base + m.range.location, length: m.range.length)
                    findings.append(Finding(range: abs, message: "Duplicate id \"\(value)\""))
                } else {
                    seenIDs.insert(value)
                }
            }
        }

        // Unquoted attribute value followed by a bareword (likely a value broken by a space,
        // e.g. `class=foo bar`). Skip when the trailing word is a known boolean attribute.
        if let unquotedRegex = unquotedRegex {
            for m in unquotedRegex.matches(in: attrs, options: [], range: attrFull) {
                let trailingRange = m.range(at: 2)
                guard trailingRange.location != NSNotFound else { continue }
                let trailing = attrNS.substring(with: trailingRange).lowercased()
                if booleanAttributes.contains(trailing) { continue }
                let abs = NSRange(location: base + m.range.location, length: m.range.length)
                findings.append(
                    Finding(range: abs, message: "Unquoted attribute value — wrap in quotes"))
            }
        }
    }

    /// Captures an `id` attribute value: group 1 = quoted contents, group 2 = unquoted.
    nonisolated(unsafe) private static let idRegex = try? NSRegularExpression(
        pattern: "\\bid\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))",
        options: [.caseInsensitive])

    /// Captures an unquoted attribute value (group 1) immediately followed by a bareword
    /// (group 2) with no `=` of its own — the signature of a value broken by a space.
    nonisolated(unsafe) private static let unquotedRegex = try? NSRegularExpression(
        pattern: "[a-zA-Z-]+\\s*=\\s*([^\"'\\s/>]+)\\s+([a-zA-Z][a-zA-Z0-9-]*)(?![a-zA-Z0-9-])(?!\\s*=)",
        options: [])
}
