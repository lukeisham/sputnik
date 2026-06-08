import SwiftUI
import PDFKit
import AppKit

/// Toolbar strip for the PDF Viewer panel.
///
/// Contains page navigation (Prev/Next, page counter), zoom controls (out / scale label /
/// in), rotation, sidebar toggles (TOC, Thumbnails), and an overflow menu (Print, Save As,
/// Reveal in Finder). Uses `SputnikColor`, `SputnikSpacing`, and `SputnikFont` throughout.
public struct PDFToolbarView: View {

    // MARK: - Bindings

    @Bindable var viewModel: PDFViewerViewModel

    // MARK: - Body

    public var body: some View {
        HStack(spacing: SputnikSpacing.xs) {
            navigationGroup
            Divider().frame(height: 16)
            zoomGroup
            Divider().frame(height: 16)
            rotateButton
            Divider().frame(height: 16)
            sidebarGroup
            Spacer()
            overflowMenu
        }
        .padding(.horizontal, SputnikSpacing.md)
        .padding(.vertical, SputnikSpacing.xs)
        .background(SputnikColor.secondaryBackground)
    }

    // MARK: - Navigation group

    private var navigationGroup: some View {
        HStack(spacing: SputnikSpacing.xs) {
            Button {
                viewModel.navigatePrevious()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: SputnikFont.caption, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(SputnikColor.secondaryText)
            .disabled(viewModel.currentPageIndex <= 0 || viewModel.document == nil)
            .help("Previous Page")

            Text(pageLabel)
                .font(.system(size: SputnikFont.caption, weight: .medium, design: .monospaced))
                .foregroundStyle(SputnikColor.primaryText)
                .frame(minWidth: 72, alignment: .center)

            Button {
                viewModel.navigateNext()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: SputnikFont.caption, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(SputnikColor.secondaryText)
            .disabled(viewModel.currentPageIndex >= viewModel.totalPageCount - 1 || viewModel.document == nil)
            .help("Next Page")
        }
    }

    private var pageLabel: String {
        guard viewModel.document != nil else { return "—" }
        return "Page \(viewModel.currentPageIndex + 1) / \(viewModel.totalPageCount)"
    }

    // MARK: - Zoom group

    private var zoomGroup: some View {
        HStack(spacing: SputnikSpacing.xs) {
            Button {
                viewModel.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: SputnikFont.caption))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(SputnikColor.secondaryText)
            .disabled(viewModel.scaleFactor <= 0.25 && !viewModel.isFitToWidth || viewModel.document == nil)
            .help("Zoom Out")

            Button {
                viewModel.toggleFitToWidth()
            } label: {
                Text(scaleLabel)
                    .font(.system(size: SputnikFont.caption, weight: .medium, design: .monospaced))
                    .foregroundStyle(viewModel.isFitToWidth ? SputnikColor.accent : SputnikColor.primaryText)
            }
            .buttonStyle(.borderless)
            .help(viewModel.isFitToWidth ? "Fit to Width (click to unlock)" : "Click to Fit Width")
            .frame(minWidth: 44, alignment: .center)

            Button {
                viewModel.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: SputnikFont.caption))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(SputnikColor.secondaryText)
            .disabled(viewModel.scaleFactor >= 4.0 || viewModel.document == nil)
            .help("Zoom In")
        }
    }

    private var scaleLabel: String {
        if viewModel.isFitToWidth { return "Fit" }
        return "\(Int(viewModel.scaleFactor * 100))%"
    }

    // MARK: - Rotate

    private var rotateButton: some View {
        Button {
            viewModel.rotateClockwise()
        } label: {
            Image(systemName: "rotate.right")
                .font(.system(size: SputnikFont.caption))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(SputnikColor.secondaryText)
        .disabled(viewModel.document == nil)
        .help("Rotate 90° Clockwise")
    }

    // MARK: - Sidebar toggles

    private var sidebarGroup: some View {
        HStack(spacing: SputnikSpacing.xs) {
            Button {
                viewModel.isTOCVisible.toggle()
            } label: {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: SputnikFont.caption))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(viewModel.isTOCVisible ? SputnikColor.accent : SputnikColor.secondaryText)
            .disabled(viewModel.document == nil)
            .help("Table of Contents")

            Button {
                viewModel.isThumbnailsVisible.toggle()
            } label: {
                Image(systemName: "square.grid.3x2")
                    .font(.system(size: SputnikFont.caption))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(viewModel.isThumbnailsVisible ? SputnikColor.accent : SputnikColor.secondaryText)
            .disabled(viewModel.document == nil)
            .help("Thumbnails")
        }
    }

    // MARK: - Overflow menu

    private var overflowMenu: some View {
        Menu {
            Button("Print…") { printDocument() }
                .disabled(viewModel.document == nil)

            Button("Save As…") { saveAs() }
                .disabled(viewModel.document == nil)

            Divider()

            Button("Reveal in Finder") { revealInFinder() }
                .disabled(viewModel.document?.documentURL == nil)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: SputnikFont.caption))
                .foregroundStyle(SputnikColor.secondaryText)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24, height: 24)
    }

    // MARK: - Actions

    private func printDocument() {
        // Printing is delegated to PDFView (which holds the NSPrintOperation context).
        // `printAction` is wired by PDFKitView.makeNSView and calls PDFView.print(with:autoRotate:).
        viewModel.printAction?()
    }

    private func saveAs() {
        guard let data = viewModel.document?.dataRepresentation() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = viewModel.document?.documentURL?.lastPathComponent ?? "document.pdf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    private func revealInFinder() {
        guard let url = viewModel.document?.documentURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
