import SwiftUI

/// A horizontal tab bar that reflects `AppState.openDocuments` and drives
/// `AppState.activeDocumentID`.
///
/// Defined in Foundation 2.4 (shared UI/UX primitives) so every module that hosts
/// a document panel can embed the same tab bar without duplicating the logic (SR-1).
///
/// **Writers:** tapping a tab sets `activeDocumentID` directly on `AppState` (permitted
/// because this view is part of Foundation, not an external module). Close buttons call
/// the `onClose` callback so the caller — typically the concrete `InterPanelRouter` —
/// can run the unsaved-changes guard before removing the session.
///
/// **Usage:**
/// ```swift
/// DocumentTabBar { id in
///     Task { await router.close(id) }
/// }
/// ```
public struct DocumentTabBar: View {

    @Environment(AppState.self) private var appState

    /// Called when the user taps the close button on a tab.
    /// The concrete `InterPanelRouter` should be wired in here to run the
    /// `isDirty` guard before removing the session from `AppState.openDocuments`.
    private let onClose: (UUID) -> Void

    /// The UUID of the tab currently being dragged, used to dim the drag-source tab.
    @State private var draggingID: UUID? = nil

    // MARK: - Init

    /// Creates a `DocumentTabBar`.
    /// - Parameter onClose: Callback invoked with the session `UUID` to close.
    public init(onClose: @escaping (UUID) -> Void) {
        self.onClose = onClose
    }

    // MARK: - Body

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(appState.openDocuments) { session in
                    TabItem(
                        session: session,
                        isActive: session.id == appState.activeDocumentID,
                        onSelect: {
                            appState.activeDocumentID = session.id
                        },
                        onClose: {
                            onClose(session.id)
                        }
                    )
                    .opacity(draggingID == session.id ? 0.4 : 1.0)
                    // Drag source: vend the tab's UUID as a plain-text NSItemProvider.
                    .onDrag {
                        draggingID = session.id
                        return NSItemProvider(object: session.id.uuidString as NSString)
                    }
                    // Drop target: reorder when another tab is dropped here.
                    .onDrop(of: ["public.plain-text"], isTargeted: nil) { providers in
                        guard let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                            guard let uuidString = item as? String,
                                  let fromID = UUID(uuidString: uuidString)
                            else { return }
                            Task { @MainActor in
                                guard fromID != session.id,
                                      let fromIndex = appState.openDocuments.firstIndex(where: { $0.id == fromID }),
                                      let toIndex = appState.openDocuments.firstIndex(where: { $0.id == session.id })
                                else { draggingID = nil; return }
                                // Adjust offset: Array.move semantics require +1 when inserting after.
                                let toOffset = toIndex < fromIndex ? toIndex : toIndex + 1
                                appState.moveDocument(fromOffsets: IndexSet(integer: fromIndex), toOffset: toOffset)
                                draggingID = nil
                            }
                        }
                        return true
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .frame(height: SputnikSpacing.tabBarHeight)
        .background(SputnikColor.tabBarBackground)
    }
}

// MARK: - TabItem

/// A single tab within `DocumentTabBar`.
private struct TabItem: View {

    /// The session this tab represents — observed so the label reacts to renames
    /// (e.g. after Save As) and dirty-dot changes without a full list rebuild.
    @State private var session: DocumentSession

    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    init(
        session: DocumentSession,
        isActive: Bool,
        onSelect: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self._session = State(initialValue: session)
        self.isActive = isActive
        self.onSelect = onSelect
        self.onClose = onClose
    }

    var body: some View {
        HStack(spacing: SputnikSpacing.tabItemSpacing) {
            // Dirty-state indicator dot
            if session.isDirty {
                Circle()
                    .fill(SputnikColor.accentPrimary)
                    .frame(width: 6, height: 6)
            }

            // Filename label
            Text(tabLabel)
                .font(.system(size: SputnikFont.caption, weight: isActive ? .semibold : .regular))
                .foregroundStyle(
                    isActive ? SputnikColor.primaryText : SputnikColor.secondaryText
                )
                .lineLimit(1)

            // Close button
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(SputnikColor.secondaryText)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Close tab")
        }
        .padding(.horizontal, SputnikSpacing.tabItemPadding)
        .frame(height: SputnikSpacing.tabBarHeight)
        .background(
            isActive
                ? SputnikColor.tabBarActiveBackground
                : Color.clear
        )
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(SputnikColor.accentPrimary)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    // MARK: - Helpers

    /// Display name for the tab: the filename, or "Untitled" for unsaved documents.
    private var tabLabel: String {
        session.url?.lastPathComponent ?? "Untitled"
    }
}

// MARK: - Design-token extensions for the tab bar
//
// These constants extend the existing `SputnikSpacing` namespace (defined in
// DesignTokens.swift) rather than duplicating them in a separate file, because
// they are tightly coupled to the tab bar's layout geometry and have no other consumer.

extension SputnikSpacing {
    /// Total height of the `DocumentTabBar` strip.
    public static let tabBarHeight: CGFloat = 32
    /// Horizontal padding inside each `TabItem`.
    public static let tabItemPadding: CGFloat = 10
    /// Spacing between elements inside a `TabItem`.
    public static let tabItemSpacing: CGFloat = 5
}

extension SputnikColor {
    /// Background of the entire tab bar strip.
    public static var tabBarBackground: Color {
        Color(nsColor: NSColor.windowBackgroundColor).opacity(0.95)
    }
    /// Background of the currently active tab.
    public static var tabBarActiveBackground: Color {
        Color(nsColor: NSColor.controlBackgroundColor)
    }
}
