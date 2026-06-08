import SwiftUI

/// Root layout that reserves every named panel slot and the pinned Terminal strip.
///
/// The centre-upper slot includes a `DocumentTabBar` above its content area so that
/// every document panel type (text editor, PDF viewer, etc.) shares the same tab bar
/// without each module re-implementing it.
///
/// Real panels (modules 3–8) will replace the placeholder `Color` views once each
/// module is built. The Terminal area is pinned at the bottom and is not part of the
/// relocatable slot system.
public struct ContentView: View {

    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Main three-column area
            HStack(spacing: 1) {
                // Left slot
                slotPlaceholder(position: .left, color: .blue.opacity(0.10))

                // Centre column — tab bar + upper panel + optional lower panel
                VStack(spacing: 0) {
                    // Shared tab bar sits above the editor slot (spec 2.4.2.5).
                    // The `onClose` callback removes the session from AppState directly
                    // here in the Foundation layer; when the concrete InterPanelRouter
                    // is wired up (app assembly), this closure should delegate to
                    // `router.close(id)` so the dirty-check guard runs.
                    DocumentTabBar { id in
                        if let index = appState.openDocuments.firstIndex(where: { $0.id == id }) {
                            let wasActive = appState.activeDocumentID == id
                            appState.openDocuments.remove(at: index)
                            if wasActive {
                                // Activate the neighbour closest to the removed tab.
                                appState.activeDocumentID = appState.openDocuments
                                    .indices
                                    .contains(max(0, index - 1))
                                        ? appState.openDocuments[max(0, index - 1)].id
                                        : appState.openDocuments.first?.id
                            }
                        }
                    }

                    Divider()

                    slotPlaceholder(position: .centerUpper, color: .green.opacity(0.10))

                    slotPlaceholder(position: .centerLower, color: .purple.opacity(0.10))
                }

                // Right slot
                slotPlaceholder(position: .right, color: .orange.opacity(0.10))
            }

            Divider()

            // Terminal strip — always visible, not a relocatable slot
            terminalPlaceholder
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    // MARK: - Private helpers

    private func slotPlaceholder(position: PanelPosition, color: Color) -> some View {
        ZStack {
            color
            Text(position.rawValue)
                .font(.system(size: SputnikFont.caption, weight: .medium, design: .monospaced))
                .foregroundStyle(SputnikColor.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var terminalPlaceholder: some View {
        ZStack {
            SputnikColor.terminalBackground
            Text("Terminal (module 7)")
                .font(.system(size: SputnikFont.caption, weight: .medium, design: .monospaced))
                .foregroundStyle(SputnikColor.terminalForeground)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }
}
