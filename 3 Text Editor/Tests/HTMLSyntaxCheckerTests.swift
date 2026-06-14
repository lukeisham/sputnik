// HTMLSyntaxCheckerTests.swift
// Tests for the lightweight HTML structural checker (3.4).
//
// The structural logic lives in the pure, off-main `HTMLSyntaxChecker.scan(_:)` function,
// so the bulk of these tests drive it directly and assert on findings (deterministic, no
// async). A smaller set exercises the live checker for gating, annotation hit-testing, and
// session dismissal. Spelling-overlap suppression depends on a live `NSSpellChecker` pass
// and is verified manually (see the plan's verification checklist).

import AppKit
import Foundation
import FoundationModule
import Testing

@testable import TextEditorModule

// MARK: - Test helpers

@MainActor
private final class HTMLMockPersistence: PersistenceService {
    func restore() async -> LayoutState { .default }
    func flushLayout(_: LayoutState) {}
    func flushLayoutSync(_: LayoutState) {}
    func restoreWindows() async -> [WindowDescriptor] { [] }
    func saveWindows(_: [WindowDescriptor]) {}
    func saveWindowsSync(_: [WindowDescriptor]) {}
    func writeRecovery(for: URL, content: String) {}
    func clearRecovery(for: URL) {}
    func pendingRecoveryNames() -> [String] { [] }
    func saveSetting<T: Encodable>(_: T, forKey: String) {}
    func loadSetting<T: Decodable>(forKey: String) -> T? { nil }
    func saveScratchpad(text: String) {}
    func loadScratchpadText() -> String { "" }
    func saveScratchpadDockedWidth(_: CGFloat) {}
    func loadScratchpadDockedWidth() -> CGFloat { 280 }
}

@MainActor
private struct HTMLCheckerFixture {
    let textView: NSTextView
    let viewModel: EditorViewModel
    let settings: SettingsStore
    let checker: HTMLSyntaxChecker

    init(text: String, htmlMode: Bool = true, enabled: Bool = true) {
        let persistence = HTMLMockPersistence()
        textView = NSTextView()
        textView.string = text
        viewModel = EditorViewModel(appState: AppState(), persistenceService: persistence)
        viewModel.htmlModeActive = htmlMode
        settings = SettingsStore(persistence: persistence)
        settings.htmlSyntaxCheckEnabled = enabled
        checker = HTMLSyntaxChecker(textView: textView, viewModel: viewModel, settings: settings)
    }
}

/// Runs the checker and waits briefly for the off-main scan + render to settle.
@MainActor
private func runAndSettle(_ checker: HTMLSyntaxChecker) async {
    checker.recheckNow()
    try? await Task.sleep(nanoseconds: 150_000_000)
}

private func messages(_ findings: [HTMLSyntaxChecker.Finding]) -> [String] {
    findings.map { $0.message }
}

// MARK: - Scan: tag balancing

struct HTMLScanTagTests {

    @Test func unclosedDivProducesUnclosedFinding() {
        let findings = HTMLSyntaxChecker.scan("<div>text")
        #expect(findings.count == 1)
        #expect(findings.first?.message == "Unclosed <div>")
        #expect(findings.first?.range == NSRange(location: 0, length: 5))
    }

    @Test func properlyClosedDivProducesNoFinding() {
        #expect(HTMLSyntaxChecker.scan("<div>text</div>").isEmpty)
    }

    @Test func mismatchedClosingTagProducesFinding() {
        let findings = HTMLSyntaxChecker.scan("<span><div>text</span></div>")
        #expect(messages(findings).contains { $0.hasPrefix("Mismatched closing tag") })
    }

    @Test func voidElementsDoNotNeedClosing() {
        #expect(HTMLSyntaxChecker.scan("<br><hr><img src=\"x\"><input type=\"text\">").isEmpty)
    }

    @Test func nestedSameTagsAreValid() {
        #expect(HTMLSyntaxChecker.scan("<div><div></div></div>").isEmpty)
    }

    @Test func selfClosedBlockTagIsNotTracked() {
        #expect(HTMLSyntaxChecker.scan("<div/>").isEmpty)
    }

    @Test func multipleUnclosedTagsAreAllReported() {
        let findings = HTMLSyntaxChecker.scan("<section><article>hi")
        #expect(findings.count == 2)
        #expect(messages(findings).contains("Unclosed <section>"))
        #expect(messages(findings).contains("Unclosed <article>"))
    }

    @Test func unknownTagsAreIgnored() {
        // Custom/unknown elements are neither tracked nor flagged.
        #expect(HTMLSyntaxChecker.scan("<custom-element>hi").isEmpty)
    }

    @Test func emptyDocumentProducesNoFindings() {
        #expect(HTMLSyntaxChecker.scan("").isEmpty)
    }

    @Test func headingTagsAreBalanced() {
        #expect(HTMLSyntaxChecker.scan("<h1>Title</h1>").isEmpty)
        #expect(HTMLSyntaxChecker.scan("<h2>Title").count == 1)
    }
}

// MARK: - Scan: attributes

struct HTMLScanAttributeTests {

    @Test func unquotedAttributeBrokenBySpaceIsFlagged() {
        let findings = HTMLSyntaxChecker.scan("<img class=foo bar>")
        #expect(messages(findings).contains { $0.hasPrefix("Unquoted attribute") })
    }

    @Test func quotedAttributeWithSpaceIsValid() {
        #expect(HTMLSyntaxChecker.scan("<img class=\"foo bar\">").isEmpty)
    }

    @Test func unquotedValueFollowedByBooleanAttributeIsNotFlagged() {
        // `required` is a valueless boolean attribute, not a broken value.
        #expect(HTMLSyntaxChecker.scan("<input type=text required>").isEmpty)
    }

    @Test func unquotedValueFollowedByAnotherAttributeIsNotFlagged() {
        // `target=_blank` is a separate attribute, not a broken value.
        #expect(HTMLSyntaxChecker.scan("<img src=a.png target=_blank>").isEmpty)
    }

    @Test func duplicateIdIsFlagged() {
        let findings = HTMLSyntaxChecker.scan("<div id=\"main\"></div><p id=\"main\"></p>")
        #expect(messages(findings).contains("Duplicate id \"main\""))
    }

    @Test func distinctIdsAreValid() {
        #expect(HTMLSyntaxChecker.scan("<div id=\"a\"></div><div id=\"b\"></div>").isEmpty)
    }

    @Test func firstIdOccurrenceIsNotFlagged() {
        let findings = HTMLSyntaxChecker.scan("<div id=\"only\"></div>")
        #expect(findings.isEmpty)
    }
}

// MARK: - Live checker: gating, hit-testing, dismissal

@MainActor
struct HTMLCheckerLiveTests {

    @Test func nonHtmlModeProducesNoAnnotations() async {
        let fixture = HTMLCheckerFixture(text: "<div>unclosed", htmlMode: false)
        await runAndSettle(fixture.checker)
        #expect(fixture.checker.annotations.isEmpty)
    }

    @Test func disabledViaSettingsProducesNoAnnotations() async {
        let fixture = HTMLCheckerFixture(text: "<div>unclosed", enabled: false)
        await runAndSettle(fixture.checker)
        #expect(fixture.checker.annotations.isEmpty)
    }

    @Test func activeCheckerAnnotatesUnclosedTag() async {
        let fixture = HTMLCheckerFixture(text: "<div>unclosed")
        await runAndSettle(fixture.checker)
        #expect(fixture.checker.annotations.count == 1)
        #expect(fixture.checker.annotations.first?.kind == .htmlSyntax)
    }

    @Test func annotationIsHitTestableAtTagLocation() async {
        let fixture = HTMLCheckerFixture(text: "<div>unclosed")
        await runAndSettle(fixture.checker)
        #expect(fixture.checker.annotation(at: 1) != nil)  // inside "<div>"
        #expect(fixture.checker.annotation(at: 100) == nil)  // out of range
    }

    @Test func dismissRemovesAnnotationThisSession() async {
        let fixture = HTMLCheckerFixture(text: "<div>unclosed")
        await runAndSettle(fixture.checker)
        guard let annotation = fixture.checker.annotations.first else {
            Issue.record("expected an annotation to dismiss")
            return
        }
        fixture.checker.dismiss(annotation)
        try? await Task.sleep(nanoseconds: 150_000_000)
        #expect(fixture.checker.annotations.isEmpty)
    }

    @Test func annotationsClearWhenModeSwitchesAway() async {
        let fixture = HTMLCheckerFixture(text: "<div>unclosed")
        await runAndSettle(fixture.checker)
        #expect(!fixture.checker.annotations.isEmpty)

        fixture.viewModel.htmlModeActive = false
        fixture.checker.onTextChange()  // inactive → clears synchronously
        #expect(fixture.checker.annotations.isEmpty)
    }
}

// MARK: - GrammarAnnotation.htmlSyntax kind

struct HTMLAnnotationKindTests {

    @Test func htmlSyntaxAnnotationRoundtrips() {
        let annotation = GrammarAnnotation(
            range: NSRange(location: 0, length: 5),
            kind: .htmlSyntax,
            suggestions: ["Unclosed <div>"])
        #expect(annotation.kind == .htmlSyntax)
        #expect(annotation.suggestions == ["Unclosed <div>"])
        #expect(!annotation.isSuppressed)
    }

    @Test func htmlSyntaxAnnotationEquatable() {
        let a = GrammarAnnotation(
            range: NSRange(location: 0, length: 5), kind: .htmlSyntax, suggestions: ["x"])
        let b = GrammarAnnotation(
            range: NSRange(location: 0, length: 5), kind: .htmlSyntax, suggestions: ["x"])
        #expect(a == b)
    }
}
