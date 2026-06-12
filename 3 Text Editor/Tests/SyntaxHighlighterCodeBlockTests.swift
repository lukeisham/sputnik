import AppKit
import Foundation
import Testing

@testable import TextEditorModule

// MARK: - SyntaxHighlighterCodeBlockTests

@MainActor
struct SyntaxHighlighterCodeBlockTests {

    // MARK: - HTML fenced block highlighting

    @Test func htmlTagsBlueInsideFencedBlock() async {
        let markdown = "```html\n<div class=\"main\">Hello</div>\n```"
        let attrs = await highlightMarkdown(markdown)

        let tagRange = rangeOf("<div", in: markdown)
        guard let tagRange else {
            Issue.record("Could not find <div in test string")
            return
        }

        let color = colorFor(range: tagRange, in: attrs)
        #expect(color == NSColor.systemBlue)
    }

    @Test func htmlAttributesOrangeInsideFencedBlock() async {
        let markdown = "```html\n<div class=\"main\">\n```"
        let attrs = await highlightMarkdown(markdown)

        let attrRange = rangeOf("class=\"main\"", in: markdown)
        guard let attrRange else {
            Issue.record("Could not find class attribute in test string")
            return
        }

        let color = colorFor(range: attrRange, in: attrs)
        #expect(color == NSColor.systemOrange)
    }

    @Test func htmlCommentsGrayInsideFencedBlock() async {
        let markdown = "```html\n<!-- comment -->\n<div></div>\n```"
        let attrs = await highlightMarkdown(markdown)

        let commentRange = rangeOf("<!-- comment -->", in: markdown)
        guard let commentRange else {
            Issue.record("Could not find comment in test string")
            return
        }

        let color = colorFor(range: commentRange, in: attrs)
        #expect(color == NSColor.systemGray)
    }

    @Test func nonHtmlFenceGetsNoSpecialColoring() async {
        // ```swift, ```python, etc. — no coloring, just plain monospace.
        let markdown = "```swift\nlet x = 1\n```"
        let attrs = await highlightMarkdown(markdown)

        let letRange = rangeOf("let", in: markdown)
        guard let letRange else {
            Issue.record("Could not find 'let' in test string")
            return
        }

        // 'let' should NOT be coloured for a non-html language.
        let color = colorFor(range: letRange, in: attrs)
        #expect(color == nil)
    }

    @Test func noLanguageTagIsPlain() async {
        let markdown = "```\n<div>text</div>\n```"
        let attrs = await highlightMarkdown(markdown)

        let divRange = rangeOf("<div>", in: markdown)
        guard let divRange else {
            Issue.record("Could not find <div> in test string")
            return
        }

        // No language tag → no HTML coloring.
        let color = colorFor(range: divRange, in: attrs)
        #expect(color == nil)
    }

    // MARK: - Markdown patterns excluded from code blocks

    @Test func markdownBoldNotColoredInsideFence() async {
        let markdown = "```html\n<b>**not bold**</b>\n```"
        let attrs = await highlightMarkdown(markdown)

        let boldRange = rangeOf("**not bold**", in: markdown)
        guard let boldRange else {
            Issue.record("Could not find bold pattern in test string")
            return
        }

        // Should NOT be purple (bold colour). It's inside a code block.
        let color = colorFor(range: boldRange, in: attrs)
        // It might be orange (HTML attribute) or nil — but never purple.
        #expect(color != NSColor.systemPurple)
    }

    @Test func headingsOutsideFenceStillColored() async {
        let markdown = "# Heading\n\n```html\n<div></div>\n```"
        let attrs = await highlightMarkdown(markdown)

        let headingRange = rangeOf("# Heading", in: markdown)
        guard let headingRange else {
            Issue.record("Could not find heading in test string")
            return
        }

        let color = colorFor(range: headingRange, in: attrs)
        #expect(color == NSColor.systemBlue)
    }

    // MARK: - Toggle off

    @Test func toggleOffDisablesHtmlHighlightingInFence() async {
        let markdown = "```html\n<div class=\"x\">text</div>\n```"

        let storage = NSTextStorage(string: markdown)
        let highlighter = SyntaxHighlighter(textStorage: storage)
        highlighter.codeBlockHighlightEnabled = false

        let attrs = await highlight(markdown, with: highlighter)

        let divRange = rangeOf("<div", in: markdown)
        guard let divRange else {
            Issue.record("Could not find <div in test string")
            return
        }

        // Toggle off → no HTML coloring inside the fence.
        let color = colorFor(range: divRange, in: attrs)
        #expect(color == nil)
    }

    // MARK: - Tilde fences

    @Test func tildeFenceHtmlDetected() async {
        let markdown = "~~~html\n<div></div>\n~~~"
        let attrs = await highlightMarkdown(markdown)

        let divRange = rangeOf("<div>", in: markdown)
        guard let divRange else {
            Issue.record("Could not find <div> in test string")
            return
        }

        #expect(colorFor(range: divRange, in: attrs) == NSColor.systemBlue)
    }

    // MARK: - Cache

    @Test func cacheReturnsConsistentResults() async {
        let markdown =
            "```html\n<div class=\"a\">1</div>\n```\n\n```html\n<span class=\"b\">2</span>\n```"

        let storage = NSTextStorage(string: markdown)
        let highlighter = SyntaxHighlighter(textStorage: storage)

        let attrs1 = await highlight(markdown, with: highlighter)
        let attrs2 = await highlight(markdown, with: highlighter)

        #expect(attrs1.count == attrs2.count)

        let divRange = rangeOf("<div", in: markdown)
        let spanRange = rangeOf("<span", in: markdown)

        guard let divRange, let spanRange else {
            Issue.record("Could not find tags in test string")
            return
        }

        #expect(colorFor(range: divRange, in: attrs2) == NSColor.systemBlue)
        #expect(colorFor(range: spanRange, in: attrs2) == NSColor.systemBlue)
    }

    // MARK: - Edge cases

    @Test func emptyHtmlBlockProducesNoCrash() async {
        let markdown = "```html\n```"
        _ = await highlightMarkdown(markdown)
        // Just verify no crash.
    }

    // MARK: - Helpers

    private func highlightMarkdown(_ markdown: String) async -> [(NSRange, NSColor)] {
        let storage = NSTextStorage(string: markdown)
        let highlighter = SyntaxHighlighter(textStorage: storage)
        return await highlight(markdown, with: highlighter)
    }

    private func highlight(
        _ text: String, with highlighter: SyntaxHighlighter
    ) async -> [(NSRange, NSColor)] {
        highlighter.highlight(mode: .markdown)
        try? await Task.sleep(nanoseconds: 500_000_000)

        guard
            let storage = Mirror(reflecting: highlighter)
                .children.first(where: { $0.label == "textStorage" })?.value as? NSTextStorage
        else { return [] }

        var attrs: [(NSRange, NSColor)] = []
        storage.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, _ in
            if let color = value as? NSColor {
                attrs.append((range, color))
            }
        }
        return attrs
    }

    private func rangeOf(_ substring: String, in text: String) -> NSRange? {
        let nsText = text as NSString
        let range = nsText.range(of: substring)
        guard range.location != NSNotFound else { return nil }
        return range
    }

    private func colorFor(range: NSRange, in attrs: [(NSRange, NSColor)]) -> NSColor? {
        for (attrRange, color) in attrs {
            let intersection = NSIntersectionRange(range, attrRange)
            if intersection.length > 0 {
                return color
            }
        }
        return nil
    }
}
