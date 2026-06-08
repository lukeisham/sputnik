import SwiftUI
import AppKit

/// Top-level SwiftUI view for the PDF Viewer panel.
///
/// Assembles `PDFToolbarView`, `PDFKitView`, and the two optional sidebars (TOC and
/// Thumbnails). Observes `AppState.activeDocument` and calls `viewModel.loadPDF(_:)`
/// whenever the active session changes to a `.pdf` file (SR-1).
///
/// **Layout:** occupies `PanelPosition.right` by default (see `PanelLayout.default`).
public struct PDFViewerPanel: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState

    // MARK: - State

    @State private var viewModel = PDFViewerViewModel()

    // MARK: - Init

    public init() {}

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            PDFToolbarView(viewModel: viewModel)
            Divider()
            contentArea
            Divider()
            statusBar
        }
        .background(SputnikColor.background)
        .onChange(of: appState.activeDocumentID) { _, _ in
            handleActiveDocumentChange()
        }
        .onAppear {
            handleActiveDocumentChange()
        }
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isLoading {
            loadingView
        } else if let errorMessage = viewModel.errorMessage {
            errorView(errorMessage)
        } else if viewModel.document == nil {
            emptyStateView
        } else {
            activeView
        }
    }

    // MARK: - Active layout (sidebars + PDFKitView)

    private var activeView: some View {
        HStack(spacing: 0) {
            if viewModel.isTOCVisible {
                TOCSidebarView(viewModel: viewModel)
                Divider()
            }
            if viewModel.isThumbnailsVisible {
                ThumbnailsSidebarView(viewModel: viewModel)
                Divider()
            }
            PDFKitView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Loading state

    private var loadingView: some View {
        VStack(spacing: SputnikSpacing.sm) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading PDF…")
                .font(.system(size: SputnikFont.body))
                .foregroundStyle(SputnikColor.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error state

    private func errorView(_ message: String) -> some View {
        VStack(spacing: SputnikSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Color.yellow)

            Text("Could Not Open PDF")
                .font(.system(size: SputnikFont.headline, weight: .semibold))
                .foregroundStyle(SputnikColor.primaryText)

            Text(message)
                .font(.system(size: SputnikFont.caption))
                .foregroundStyle(SputnikColor.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SputnikSpacing.xl)

            HStack(spacing: SputnikSpacing.sm) {
                Button("Try Again") {
                    Task { await viewModel.retryLoad() }
                }
                .buttonStyle(.borderedProminent)

                Button("Dismiss") {
                    viewModel.clearError()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: SputnikSpacing.sm) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 36))
                .foregroundStyle(SputnikColor.tertiaryText)

            Text("Open a PDF file to view")
                .font(.system(size: SputnikFont.body, weight: .medium))
                .foregroundStyle(SputnikColor.secondaryText)

            Button("Open…") { openPanel() }
                .buttonStyle(.bordered)
                .font(.system(size: SputnikFont.caption))
                .padding(.top, SputnikSpacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: SputnikSpacing.sm) {
            if let doc = viewModel.document {
                let filename = doc.documentURL?.lastPathComponent ?? "Untitled"
                let fileSizeStr = fileSizeString(for: doc.documentURL)
                let scaleStr = viewModel.isFitToWidth
                    ? "Fit"
                    : "\(Int(viewModel.scaleFactor * 100))%"

                Text("Page \(viewModel.currentPageIndex + 1) of \(viewModel.totalPageCount)")
                separatorDot
                Text(filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                separatorDot
                Text(fileSizeStr)
                separatorDot
                Text(scaleStr)
            } else {
                Text("No document open")
            }
            Spacer()
        }
        .font(.system(size: SputnikFont.caption, design: .monospaced))
        .foregroundStyle(SputnikColor.tertiaryText)
        .padding(.horizontal, SputnikSpacing.md)
        .padding(.vertical, SputnikSpacing.xs)
        .background(SputnikColor.secondaryBackground)
    }

    private var separatorDot: some View {
        Text("·")
            .foregroundStyle(SputnikColor.tertiaryText)
    }

    // MARK: - Document change handler

    private func handleActiveDocumentChange() {
        guard let session = appState.activeDocument,
              session.fileType == .pdf,
              let url = session.url
        else {
            // Non-PDF or no document — don't clear so we don't flash empty state
            // when switching back from a non-PDF tab while a PDF is already loaded.
            return
        }

        // Only reload if the URL actually changed.
        if viewModel.document?.documentURL != url {
            Task { await viewModel.loadPDF(url) }
        }
    }

    // MARK: - Open panel

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            appState.openDocument(url: url)
        }
    }

    // MARK: - Helpers

    private func fileSizeString(for url: URL?) -> String {
        guard let url,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64
        else { return "—" }
        let mb = Double(size) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }
}
