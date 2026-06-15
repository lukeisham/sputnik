import AppKit
import FoundationModule
import SwiftUI

// MARK: - JSONTextView (NSViewRepresentable)

/// Read-only `NSTextView` that displays an `NSAttributedString` with JSON syntax colouring.
///
/// The attributed string is produced by `JSONViewerViewModel.colorize(_:)` on a background
/// task; this view renders it on the main thread only. `isEditable = false` enforces SR-3
/// (low RAM — no undo stack) and prevents accidental edits.
private struct JSONTextViewRepresentable: NSViewRepresentable {

    let content: NSAttributedString?
    let viewModel: JSONViewerViewModel

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        viewModel.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let attributed = content ?? NSAttributedString()
        textView.textStorage?.setAttributedString(attributed)
    }
}

// MARK: - JSONViewerPanel

/// Read-only viewer for `.json` files inside the HTML Preview panel slot.
///
/// Displays a header bar ("JSON VIEWER" + filename), a Copy button, a Prettify/Minify
/// toggle, an optional error banner, and a syntax-coloured `NSTextView`.
///
/// Owns a `JSONViewerViewModel` created on `init` and kept alive for the panel's lifetime.
/// The raw text is sourced from `AppState.activeDocument?.text` and pushed to the view-model
/// on every document change.
public struct JSONViewerPanel: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState

    // MARK: - State

    @State private var viewModel = JSONViewerViewModel()

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if let errorMessage = viewModel.lastError {
                errorBanner(errorMessage)
            }

            if viewModel.isEmpty {
                emptyStatePlaceholder
            } else {
                JSONTextViewRepresentable(
                    content: viewModel.renderedContent,
                    viewModel: viewModel
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .trailing) {
            Minimap()
        }
        .background(SputnikColor.editorBackground)
        .onChange(of: appState.activeDocumentID) { _, _ in
            refreshText()
        }
        .onChange(of: appState.activeDocument?.text) { _, newText in
            viewModel.rawText = newText ?? ""
        }
        .onAppear {
            refreshText()
            appState.activeWindow?.minimapTargetScrollView = viewModel.scrollView
        }
        .onDisappear {
            if appState.activeWindow?.minimapTargetScrollView === viewModel.scrollView {
                appState.activeWindow?.minimapTargetScrollView = nil
            }
        }
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(spacing: SputnikSpacing.sm) {
            Text("JSON VIEWER")
                .font(.system(size: SputnikFont.caption, weight: .semibold, design: .default))
                .foregroundStyle(SputnikColor.secondaryText)

            if let name = appState.activeDocument?.url?.lastPathComponent {
                Text("—")
                    .foregroundStyle(SputnikColor.tertiaryText)
                Text(name)
                    .font(.system(size: SputnikFont.caption, weight: .medium, design: .default))
                    .foregroundStyle(SputnikColor.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if appState.activeDocument != nil {
                Text("— Untitled")
                    .font(.system(size: SputnikFont.caption, weight: .medium, design: .default))
                    .foregroundStyle(SputnikColor.tertiaryText)
            }

            Spacer()

            // Prettify / Minify toggle.
            Button {
                viewModel.toggleDisplayMode()
            } label: {
                Text(viewModel.displayMode == .pretty ? "Minify" : "Prettify")
                    .font(.system(size: SputnikFont.caption, weight: .medium, design: .default))
            }
            .buttonStyle(.plain)
            .foregroundStyle(SputnikColor.secondaryText)
            .help(
                viewModel.displayMode == .pretty
                    ? "Collapse to one line" : "Expand with indentation")

            // Copy button.
            Button {
                copyToClipboard()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: SputnikFont.caption))
            }
            .buttonStyle(.plain)
            .foregroundStyle(SputnikColor.secondaryText)
            .help("Copy formatted JSON")
        }
        .padding(.horizontal, SputnikSpacing.md)
        .padding(.vertical, SputnikSpacing.xs)
        .frame(height: SputnikLayout.headerHeight)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: SputnikSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: SputnikFont.caption))
                .foregroundStyle(Color.yellow)
            Text("JSON error: \(message)")
                .font(.system(size: SputnikFont.caption))
                .foregroundStyle(SputnikColor.secondaryText)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, SputnikSpacing.md)
        .padding(.vertical, SputnikSpacing.xs)
        .background(Color.yellow.opacity(0.10))
    }

    // MARK: - Empty state

    private var emptyStatePlaceholder: some View {
        VStack(spacing: SputnikSpacing.sm) {
            Image(systemName: "curlybraces")
                .font(.system(size: 32))
                .foregroundStyle(SputnikColor.tertiaryText)
            Text("Empty JSON file")
                .font(.system(size: SputnikFont.body, weight: .medium))
                .foregroundStyle(SputnikColor.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func refreshText() {
        viewModel.rawText = appState.activeDocument?.text ?? ""
    }

    private func copyToClipboard() {
        guard let attributed = viewModel.renderedContent else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(attributed.string, forType: .string)
    }
}
