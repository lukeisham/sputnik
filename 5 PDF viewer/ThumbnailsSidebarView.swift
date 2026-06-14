import SwiftUI
import FoundationModule
import PDFKit

/// Lazy-loading thumbnail grid for visual page navigation.
///
/// Thumbnails are generated on `Task(priority: .background)` as each cell scrolls into
/// view and cached in `PDFViewerViewModel.thumbnailCache`. Tapping a cell navigates to
/// that page. The current page is highlighted with an accent border.
public struct ThumbnailsSidebarView: View {

    // MARK: - Bindings

    @Bindable var viewModel: PDFViewerViewModel

    // MARK: - Layout

    private let columns = [
        GridItem(.flexible(), spacing: SputnikSpacing.sm),
        GridItem(.flexible(), spacing: SputnikSpacing.sm),
    ]

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(SputnikColor.secondaryBackground)
        .frame(width: 220)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("THUMBNAILS")
                .font(.system(size: SputnikFont.caption, weight: .semibold))
                .foregroundStyle(SputnikColor.secondaryText)
            Spacer()
        }
        .padding(.horizontal, SputnikSpacing.sm)
        .padding(.vertical, SputnikSpacing.xs)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.totalPageCount == 0 {
            VStack {
                Spacer()
                Text("No thumbnails")
                    .font(.system(size: SputnikFont.caption))
                    .foregroundStyle(SputnikColor.tertiaryText)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: SputnikSpacing.sm) {
                    ForEach(0..<viewModel.totalPageCount, id: \.self) { index in
                        ThumbnailCell(
                            index: index,
                            isCurrentPage: index == viewModel.currentPageIndex,
                            viewModel: viewModel
                        )
                    }
                }
                .padding(SputnikSpacing.sm)
            }
        }
    }
}

// MARK: - Thumbnail cell

private struct ThumbnailCell: View {

    let index: Int
    let isCurrentPage: Bool
    @Bindable var viewModel: PDFViewerViewModel

    var body: some View {
        VStack(spacing: SputnikSpacing.xs) {
            thumbnailImage
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isCurrentPage ? SputnikColor.accent : Color.clear, lineWidth: 2)
                )
                .onTapGesture {
                    viewModel.navigateTo(page: index)
                }

            Text("\(index + 1)")
                .font(.system(size: SputnikFont.caption - 1, design: .monospaced))
                .foregroundStyle(isCurrentPage ? SputnikColor.accent : SputnikColor.tertiaryText)
        }
        .onAppear {
            viewModel.generateThumbnail(for: index)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityAddTraits(isCurrentPage ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Go to this page")
        .accessibilityAction { viewModel.navigateTo(page: index) }
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let nsImage = viewModel.thumbnailCache.object(forKey: index as NSNumber) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 90, maxHeight: 120)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .shadow(color: .black.opacity(0.12), radius: 2, x: 0, y: 1)
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(SputnikColor.background)
                .frame(width: 90, height: 120)
                .overlay {
                    Image(systemName: "doc")
                        .font(.system(size: 20))
                        .foregroundStyle(SputnikColor.tertiaryText)
                }
        }
    }
}
