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
                // Left slot — Project File Tree (module 6)
                FileTreePanel()
                    .frame(width: 240)
                    .frame(maxHeight: .infinity)

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
                                appState.activeDocumentID =
                                    appState.openDocuments
                                        .indices
                                        .contains(max(0, index - 1))
                                    ? appState.openDocuments[max(0, index - 1)].id
                                    : appState.openDocuments.first?.id
                            }
                        }
                    }

                    Divider()

                    slotPlaceholder(position: .centerUpper, color: .green.opacity(0.10))

                    MarkdownPreviewPanel()
                }

                // Right slot — help panels or PDF/HTML preview stack.
                // When a help topic is requested, the matching help panel replaces the
                // normal document preview stack.
                rightColumn
            }

            Divider()

            // Terminal strip — always visible, not a relocatable slot
            terminalPlaceholder

            Divider()

            // Bottom status bar — satellite icon, AI model, context, RAM, CPU (F-5)
            StatusBarView()
        }
        .frame(minWidth: 900, minHeight: 600)
        .overlay(alignment: .bottomTrailing) {
            ScratchpadPanel(
                isVisible: Binding(
                    get: { appState.scratchpadVisible },
                    set: { appState.scratchpadVisible = $0 }
                ),
                text: Binding(
                    get: { appState.scratchpadText },
                    set: { appState.scratchpadText = $0 }
                ),
                scratchpadFrame: Binding(
                    get: { appState.scratchpadFrame },
                    set: { appState.scratchpadFrame = $0 }
                )
            )
        }
    }

    // MARK: - Private helpers

    /// Right-column content: shows the requested help panel when `requestedHelpTopic`
    /// is set, or the PDF/HTML preview stack otherwise.
    ///
    /// All five views are kept in the view tree at all times via opacity so that each
    /// panel's `@State` (loaded topics, scroll position) survives topic switches without
    /// re-triggering the async index load.
    @ViewBuilder
    private var rightColumn: some View {
        let topic = appState.requestedHelpTopic
        ZStack {
            VStack(spacing: 0) {
                PDFViewerPanel()
                Divider()
                HTMLPreviewPanel()
            }
            .opacity(topic == nil || topic == .sputnik ? 1 : 0)

            ASCIIArtHelpPanelView()
                .opacity(topic == .asciiArt ? 1 : 0)

            MarkdownHelpPanelView()
                .opacity(topic == .markdown ? 1 : 0)

            HTMLHelpPanelView()
                .opacity(topic == .html ? 1 : 0)

            GrammarHelpPanelView()
                .opacity(topic == .grammar ? 1 : 0)
        }
    }

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
