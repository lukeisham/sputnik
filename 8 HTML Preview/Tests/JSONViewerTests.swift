// JSONViewerTests.swift
// Tests for JSONViewerViewModel (Module 8).

import AppKit
import Foundation
import Testing

@testable import HTMLPreviewModule

// MARK: - JSONViewerViewModelTests

@MainActor
struct JSONViewerViewModelTests {

    // MARK: Happy path — valid JSON

    @Test func validObjectRendersPrettily() async throws {
        let vm = JSONViewerViewModel()
        vm.rawText = #"{"name":"Ada","count":1}"#
        try await Task.sleep(nanoseconds: 300_000_000)
        let rendered = vm.renderedContent
        #expect(rendered != nil)
        #expect(rendered?.length ?? 0 > 0)
        #expect(vm.lastError == nil)
    }

    @Test func validArrayRenders() async throws {
        let vm = JSONViewerViewModel()
        vm.rawText = "[1, 2, 3]"
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vm.renderedContent != nil)
        #expect(vm.lastError == nil)
    }

    @Test func validBooleanFragmentRenders() async throws {
        let vm = JSONViewerViewModel()
        vm.rawText = "true"
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vm.renderedContent != nil)
        #expect(vm.lastError == nil)
    }

    @Test func validNullFragmentRenders() async throws {
        let vm = JSONViewerViewModel()
        vm.rawText = "null"
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vm.renderedContent != nil)
        #expect(vm.lastError == nil)
    }

    // MARK: Error handling

    @Test func invalidJSONSetsLastError() async throws {
        let vm = JSONViewerViewModel()
        vm.rawText = "{bad json}"
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vm.lastError != nil)
    }

    @Test func trailingCommaSetsError() async throws {
        let vm = JSONViewerViewModel()
        vm.rawText = #"{"a": 1,}"#
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vm.lastError != nil)
    }

    @Test func unclosedObjectSetsError() async throws {
        let vm = JSONViewerViewModel()
        vm.rawText = #"{"a": 1"#
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vm.lastError != nil)
    }

    // MARK: Empty / whitespace

    @Test func emptyTextProducesNoError() async throws {
        let vm = JSONViewerViewModel()
        vm.rawText = ""
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vm.lastError == nil)
        #expect(vm.isEmpty)
    }

    @Test func whitespaceOnlyIsEmpty() async throws {
        let vm = JSONViewerViewModel()
        vm.rawText = "   \n\t  "
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vm.isEmpty)
        #expect(vm.lastError == nil)
    }

    // MARK: Display mode toggle

    @Test func defaultDisplayModeIsPretty() {
        let vm = JSONViewerViewModel()
        #expect(vm.displayMode == .pretty)
    }

    @Test func toggleDisplayModeChangesToMinified() {
        let vm = JSONViewerViewModel()
        vm.toggleDisplayMode()
        #expect(vm.displayMode == .minified)
    }

    @Test func toggleDisplayModeTwiceRetursToPretty() {
        let vm = JSONViewerViewModel()
        vm.toggleDisplayMode()
        vm.toggleDisplayMode()
        #expect(vm.displayMode == .pretty)
    }

    @Test func minifiedOutputHasNoNewlines() async throws {
        let vm = JSONViewerViewModel()
        vm.rawText = #"{"a": 1, "b": 2}"#
        vm.toggleDisplayMode()  // switch to minified
        try await Task.sleep(nanoseconds: 300_000_000)
        let text = vm.renderedContent?.string ?? ""
        #expect(!text.contains("\n"))
    }

    @Test func prettyOutputHasNewlines() async throws {
        let vm = JSONViewerViewModel()
        vm.rawText = #"{"a": 1, "b": 2}"#
        try await Task.sleep(nanoseconds: 300_000_000)
        let text = vm.renderedContent?.string ?? ""
        #expect(text.contains("\n"))
    }

    // MARK: Colour attributes present

    @Test func renderedContentHasColorAttributes() async throws {
        let vm = JSONViewerViewModel()
        vm.rawText = #"{"key": "value", "count": 42, "flag": true}"#
        try await Task.sleep(nanoseconds: 300_000_000)
        guard let attributed = vm.renderedContent else {
            Issue.record("renderedContent should not be nil")
            return
        }
        var foundColor = false
        attributed.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            if value != nil { foundColor = true }
        }
        #expect(foundColor)
    }

    // MARK: Re-render on text change

    @Test func textChangeTriggersNewRender() async throws {
        let vm = JSONViewerViewModel()
        vm.rawText = "[1]"
        try await Task.sleep(nanoseconds: 300_000_000)
        let first = vm.renderedContent?.string

        vm.rawText = "[2, 3]"
        try await Task.sleep(nanoseconds: 300_000_000)
        let second = vm.renderedContent?.string
        #expect(first != second)
    }

    // MARK: reload()

    @Test func reloadRerenders() async throws {
        let vm = JSONViewerViewModel()
        vm.rawText = #"{"x": 1}"#
        try await Task.sleep(nanoseconds: 300_000_000)
        let before = vm.renderedContent

        vm.reload()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vm.renderedContent?.string == before?.string)
    }
}
