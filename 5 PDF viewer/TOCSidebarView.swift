import SwiftUI
import FoundationModule
import PDFKit

/// Sidebar view rendering the PDF's table of contents from `PDFOutline`.
///
/// Each `PDFOutline` node maps to a row showing its label and optional page number.
/// Tapping a row calls `PDFView.go(to:)` via the view model's navigate action.
/// Children are accessed on demand via `DisclosureGroup` — the tree is not pre-expanded.
public struct TOCSidebarView: View {

    // MARK: - Bindings

    @Bindable var viewModel: PDFViewerViewModel

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
            Text("TABLE OF CONTENTS")
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
        if let root = viewModel.document?.outlineRoot, root.numberOfChildren > 0 {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<root.numberOfChildren, id: \.self) { i in
                        if let child = root.child(at: i) {
                            OutlineRowView(outline: child, depth: 0, viewModel: viewModel)
                        }
                    }
                }
                .padding(.vertical, SputnikSpacing.xs)
            }
        } else {
            VStack {
                Spacer()
                Text("No table of contents available")
                    .font(.system(size: SputnikFont.caption))
                    .foregroundStyle(SputnikColor.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(SputnikSpacing.md)
                Spacer()
            }
        }
    }
}

// MARK: - Recursive row

/// A single TOC entry row. Recursively renders children inside a `DisclosureGroup`.
private struct OutlineRowView: View {

    let outline: PDFOutline
    let depth: Int
    @Bindable var viewModel: PDFViewerViewModel

    var body: some View {
        if outline.numberOfChildren > 0 {
            DisclosureGroup {
                ForEach(0..<outline.numberOfChildren, id: \.self) { i in
                    if let child = outline.child(at: i) {
                        OutlineRowView(outline: child, depth: depth + 1, viewModel: viewModel)
                    }
                }
            } label: {
                // Parent nodes may also carry a destination; tap the label to navigate.
                Button(action: navigateTo) {
                    rowLabel
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(depth) * SputnikSpacing.md)
            .padding(.horizontal, SputnikSpacing.sm)
        } else {
            Button(action: navigateTo) {
                rowLabel
            }
            .buttonStyle(.plain)
            .padding(.leading, CGFloat(depth) * SputnikSpacing.md + SputnikSpacing.sm)
            .padding(.vertical, 2)
        }
    }

    private var rowLabel: some View {
        HStack(spacing: SputnikSpacing.xs) {
            Text(outline.label ?? "—")
                .font(.system(size: SputnikFont.caption))
                .foregroundStyle(SputnikColor.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if let dest = outline.destination, let page = dest.page,
               let doc = viewModel.document
            {
                let pageNum = doc.index(for: page) + 1
                Text("\(pageNum)")
                    .font(.system(size: SputnikFont.caption, design: .monospaced))
                    .foregroundStyle(SputnikColor.tertiaryText)
            }
        }
        .contentShape(Rectangle())
    }

    private func navigateTo() {
        guard let dest = outline.destination,
              let page = dest.page,
              let doc = viewModel.document
        else { return }
        let index = doc.index(for: page)
        viewModel.navigateTo(page: index)
    }
}
