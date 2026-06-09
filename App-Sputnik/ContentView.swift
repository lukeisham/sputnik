import SwiftUI

/// Root layout wiring every named panel slot and the pinned Terminal strip.
///
/// Lives at the app-assembly layer (App-Sputnik/) so Foundation never imports
/// TextEditorModule or TerminalModule — the dependency arrow stays one-way (ISS-NEW-C).
public struct ContentView: View {

    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    @State private var editorViewModel = EditorViewModel()

    private let router: any InterPanelRouter

    public init(router: any InterPanelRouter) {
        self.router = router
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                // Left — Project File Tree (module 6)
                FileTreePanel()
                    .frame(width: 240)
                    .frame(maxHeight: .infinity)

                // Centre — tab bar + editor + Markdown preview
                VStack(spacing: 0) {
                    DocumentTabBar { id in
                        Task { await router.close(id) }
                    }

                    Divider()

                    EditorView(viewModel: editorViewModel, settings: settings, appState: appState)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    MarkdownPreviewPanel()
                }
                .onChange(of: appState.activeDocumentID) { _, _ in
                    editorViewModel.resetForNewFile(url: appState.activeDocument?.url)
                }

                // Right — help panels or PDF/HTML preview stack
                rightColumn
            }

            Divider()

            // Terminal strip — always visible, pinned at bottom
            TerminalView()
                .frame(maxWidth: .infinity)
                .frame(height: 200)

            Divider()

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

    // MARK: - Right column

    /// Shows the requested help panel when `requestedHelpTopic` is set, or the
    /// PDF/HTML preview stack otherwise. All five views stay in the tree so each
    /// panel's @State (loaded topics, scroll position) survives topic switches.
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
}
