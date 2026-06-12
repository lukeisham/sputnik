import FoundationModule
import SwiftUI
import UniformTypeIdentifiers

/// A single dynamic column in the panel layout.
///
/// Renders a title bar (badge, render-mode toggle pills, drag handle, close button),
/// an optional scrollable tab bar, and the panel content area provided by the caller.
///
/// The column role (active / activePair / viewOnly) drives the border style and
/// whether the content closure receives an editable or view-only configuration.
struct PanelColumnView<Content: View>: View {

    @Binding var column: PanelColumn
    let columnIndex: Int
    @Binding var layout: DynamicPanelLayout
    let columnRole: DynamicPanelLayout.ColumnRole
    let content: (PanelID, UUID?, DynamicPanelLayout.ColumnRole) -> Content

    @Environment(WindowState.self) private var windowState
    @Environment(AppState.self) private var appState

    init(
        column: Binding<PanelColumn>,
        columnIndex: Int,
        layout: Binding<DynamicPanelLayout>,
        columnRole: DynamicPanelLayout.ColumnRole,
        @ViewBuilder content: @escaping (PanelID, UUID?, DynamicPanelLayout.ColumnRole) -> Content
    ) {
        self._column = column
        self.columnIndex = columnIndex
        self._layout = layout
        self.columnRole = columnRole
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar (28 pt height)
            titleBar
                .frame(height: 28)

            Divider()

            // Scrollable tab bar (only when more than one document)
            if column.documentIDs.count > 1 {
                tabBar
                Divider()
            }

            // Panel content area
            content(column.renderMode, column.activeDocumentID, columnRole)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SputnikColor.background)
        .overlay(alignment: .top) { roleBorder }
        .contentShape(Rectangle())
        .onTapGesture {
            layout.revertToggleIfNeeded(forColumnID: column.id)
            windowState.activeColumnID = column.id
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: ColumnDropDelegate(layout: $layout, columnIndex: columnIndex)
        )
        .onDrag {
            let provider = NSItemProvider(object: column.id.uuidString as NSString)
            provider.suggestedName = column.renderMode.displayBadge ?? "panel"
            return provider
        }
    }

    // MARK: - Title bar

    @ViewBuilder
    private var titleBar: some View {
        HStack(spacing: 4) {
            // Left: badge pill (omit for .textEditor)
            if column.renderMode != .textEditor {
                badgePill
            }

            // Render-mode toggle pills (view-only text-sourced columns only)
            if columnRole == .viewOnly, isTextSourced {
                renderModeTogglePills
            }

            Spacer()

            // Centre: drag handle — purely decorative; the drag gesture lives on the
            // whole column, so hide the glyph from VoiceOver to avoid a redundant element.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(SputnikColor.secondaryText)
                .help("Drag to reorder")
                .accessibilityHidden(true)

            Spacer()

            // Right: close button
            Button(action: removeColumn) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(SputnikColor.secondaryText)
            .help("Close column")
            .accessibilityLabel("Close column")
            .accessibilityHint("Removes this \(columnAccessibilityName) column")
        }
        .padding(.horizontal, SputnikSpacing.sm)
        .padding(.vertical, 4)
        .background(SputnikColor.secondaryBackground)
    }

    /// Small badge pill showing the render mode.
    private var badgePill: some View {
        let badge = resolvedBadge
        return Group {
            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(SputnikColor.accentPrimary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(SputnikColor.accentPrimary.opacity(0.15))
                    .clipShape(Capsule())
                    .accessibilityLabel("Panel type: \(badge)")
            }
        }
    }

    /// The badge label, overriding `.pdfViewer` with `"PNG"` when the active document is an image.
    private var resolvedBadge: String? {
        if column.renderMode == .pdfViewer {
            if let docID = column.activeDocumentID,
                let doc = windowState.document(for: docID),
                doc.fileType == .image
            {
                return "PNG"
            }
        }
        return column.renderMode.displayBadge
    }

    /// A human-readable name for this column's panel type, for VoiceOver hints.
    private var columnAccessibilityName: String {
        resolvedBadge ?? column.renderMode.displayBadge ?? column.renderMode.rawValue
    }

    /// Whether this column is text-sourced (currently or originally a .textEditor).
    private var isTextSourced: Bool {
        column.renderMode == .textEditor || column.originalRenderMode == .textEditor
    }

    /// Render-mode toggle pills: compact pill buttons for TXT, MD, HTML.
    /// Only shown when the active document's extension supports toggling.
    private var renderModeTogglePills: some View {
        let modes = availableToggleModes
        return Group {
            if !modes.isEmpty {
                HStack(spacing: 2) {
                    ForEach(modes, id: \.self) { mode in
                        let isCurrent = mode == column.renderMode
                        Button(action: {
                            layout.toggleRenderMode(ofColumnID: column.id, to: mode)
                        }) {
                            Text(mode.displayBadge ?? "?")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(
                                    isCurrent
                                        ? SputnikColor.accentPrimary
                                        : SputnikColor.secondaryText
                                )
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    isCurrent
                                        ? SputnikColor.accentPrimary.opacity(0.20)
                                        : Color.clear
                                )
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            isCurrent
                                                ? SputnikColor.accentPrimary.opacity(0.4)
                                                : SputnikColor.separator,
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(mode.rawValue)
                        .accessibilityLabel("Show as \(mode.rawValue)")
                        .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    }
                }
            }
        }
    }

    /// Available toggle modes derived from the active document's file extension.
    /// Returns empty array when the column has no active document or the extension
    /// does not support toggling.
    private var availableToggleModes: [PanelID] {
        guard let docID = column.activeDocumentID else { return [] }
        guard let doc = windowState.document(for: docID),
            let ext = doc.url?.pathExtension.lowercased()
        else { return [] }
        switch ext {
        case "md", "markdown":
            return [.textEditor, .markdownPreview]
        case "html", "htm":
            return [.textEditor, .htmlPreview]
        default:
            return []
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(column.documentIDs.enumerated()), id: \.element) { index, docID in
                    let isActive = index == column.activeDocumentIndex
                    let label = tabLabel(for: docID)
                    Button(action: {
                        column.activeDocumentIndex = index
                        windowState.activeColumnID = column.id
                    }) {
                        HStack(spacing: 3) {
                            Text(label)
                                .font(.system(size: SputnikFont.caption))
                                .lineLimit(1)
                            if let badge = column.renderMode.displayBadge {
                                Text(badge)
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(SputnikColor.secondaryText)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            isActive
                                ? SputnikColor.accentPrimary.opacity(0.15)
                                : Color.clear
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label)
                    .accessibilityHint("Switch to this document tab")
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            .padding(.horizontal, SputnikSpacing.sm)
            .padding(.vertical, 3)
        }
        .frame(height: 26)
        .background(SputnikColor.secondaryBackground)
    }

    /// Short display label for a document tab (filename or "Untitled").
    private func tabLabel(for docID: UUID) -> String {
        if let doc = windowState.document(for: docID) {
            return doc.url?.lastPathComponent ?? "Untitled"
        }
        return "?"
    }

    // MARK: - Column role border

    /// Animated border overlay based on column role.
    @ViewBuilder
    private var roleBorder: some View {
        // Differentiate Without Color note: the two active states are distinguished by
        // *shape* (solid vs dashed) and by presence/absence, not by colour alone, so they
        // remain legible with the "Differentiate Without Color" setting on.
        if column.renderMode == .textEditor, columnRole == .active, column.activeDocumentID != nil {
            // Active text editor: 2 pt solid accent
            SputnikColor.accentPrimary
                .frame(height: 2)
                .frame(maxWidth: .infinity)
                .accessibleAnimation(.easeInOut(duration: 0.15), value: columnRole)
        } else if columnRole == .activePair {
            // Active pair preview: 1 pt dashed accent at 40% opacity
            DashedLine()
                .stroke(
                    SputnikColor.accentPrimary.opacity(0.4),
                    style: SwiftUI.StrokeStyle(lineWidth: 1, dash: [4, 2])
                )
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .accessibleAnimation(.easeInOut(duration: 0.15), value: columnRole)
        }
    }

    // MARK: - Actions

    private func removeColumn() {
        // Subtle haptic to confirm the column-close action.
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment, performanceTime: .default)

        let wasActive = windowState.activeColumnID == column.id
        layout.removeColumn(id: column.id)
        if wasActive {
            windowState.activeColumnID = layout.columns.first?.id
        }
    }
}

// MARK: - Dashed line shape

/// A simple horizontal line shape, used for the active-pair dashed border.
private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
