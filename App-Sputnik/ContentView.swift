import ASCIIStudioModule
import FileTreeModule
import FoundationModule
import HTMLPreviewModule
import MarkdownPreviewModule
import Observation
import PDFViewerModule
import ResourcesModule
import SwiftUI
import TerminalModule
import TextEditorModule

/// Root layout wiring every named panel slot and the pinned Terminal strip.
///
/// Lives at the app-assembly layer (App-Sputnik/) so Foundation never imports
/// TextEditorModule or TerminalModule — the dependency arrow stays one-way (ISS-NEW-C).
public struct ContentView: View {

    @Environment(WindowState.self) private var windowState
    @Environment(SettingsStore.self) private var settings
    @Environment(PanelFocusCoordinator.self) private var focusCoordinator

    @State private var editorViewModel: EditorViewModel

    /// Per-window `@FocusState` driven by the shared `PanelFocusCoordinator`.
    /// Synced bidirectionally via `.onChange` below.
    @FocusState private var focusedPanel: PanelFocusTarget?

    private let appState: AppState
    private let router: any InterPanelRouter

    public init(
        windowState: WindowState, router: any InterPanelRouter,
        appState: AppState, persistenceService: any PersistenceService,
        focusCoordinator: PanelFocusCoordinator
    ) {
        self.appState = appState
        self.router = router
        // Create the editor view model with explicit dependency injection (ISS-056).
        _editorViewModel = State(
            initialValue: EditorViewModel(
                appState: appState,
                persistenceService: persistenceService
            )
        )
        // windowState is injected into the environment by SputnikApp, so @Environment picks it up
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Dynamic column layout
            HStack(spacing: 1) {
                ForEach(
                    Array(windowState.layout.dynamicLayout.columns.enumerated()),
                    id: \.offset
                ) { index, _ in
                    let col = windowState.layout.dynamicLayout.columns[index]
                    let role = windowState.layout.dynamicLayout.role(
                        of: col.id,
                        activeColumnID: windowState.activeColumnID
                    )
                    // Manual bindings because $windowState is not available for @Environment
                    let columnBinding = Binding<PanelColumn>(
                        get: { windowState.layout.dynamicLayout.columns[index] },
                        set: { windowState.layout.dynamicLayout.columns[index] = $0 }
                    )
                    let layoutBinding = Binding<DynamicPanelLayout>(
                        get: { windowState.layout.dynamicLayout },
                        set: { windowState.layout.dynamicLayout = $0 }
                    )
                    PanelColumnView(
                        column: columnBinding,
                        columnIndex: index,
                        layout: layoutBinding,
                        columnRole: role,
                        isFocused: focusedPanel == .column(col.id)
                    ) { panelID, documentID, columnRole in
                        panelContentView(
                            renderMode: panelID,
                            documentID: documentID,
                            columnRole: columnRole
                        )
                    }
                    .focused($focusedPanel, equals: .column(col.id))

                    if index < windowState.layout.dynamicLayout.columns.count - 1 {
                        ZStack(alignment: .leading) {
                            ResizeDivider()
                            DropZoneView(
                                insertionIndex: index + 1,
                                layout: layoutBinding
                            )
                        }
                        .frame(width: 8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { helpPanelOverlay }

            Divider()

            // Terminal strip + docked scratchpad
            HStack(spacing: 0) {
                TerminalView()
                    .focused($focusedPanel, equals: .terminal)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)

                if windowState.scratchpadVisible {
                    Divider()
                    DockedScratchpadPanel(
                        text: Binding(
                            get: { windowState.scratchpadText },
                            set: { windowState.scratchpadText = $0 }
                        ),
                        width: Binding(
                            get: { windowState.scratchpadDockedWidth },
                            set: { windowState.scratchpadDockedWidth = $0 }
                        )
                    )
                }
            }
            .frame(height: 200)

            Divider()

            StatusBarView()
        }
        .frame(minWidth: 900, minHeight: 600)
        // Sync @FocusState <-> PanelFocusCoordinator bidirectional
        .onChange(of: focusedPanel) { _, newValue in
            focusCoordinator.focusedPanel = newValue
        }
        .onChange(of: focusCoordinator.focusedPanel) { _, newValue in
            focusedPanel = newValue
        }
        .onAppear {
            // Set the initial default first responder to the active editor column
            // (or the first column if no editor column exists).
            if focusCoordinator.focusedPanel == nil,
                let firstFocus = windowState.layout.dynamicLayout.columns.first(where: {
                    $0.renderMode == .textEditor
                }) ?? windowState.layout.dynamicLayout.columns.first
            {
                let target = PanelFocusTarget.column(firstFocus.id)
                focusCoordinator.focusedPanel = target
                focusedPanel = target
            }
        }
        .toolbar {
            ToolbarItem(id: "file-tree", placement: .automatic) {
                toolbarPanelToggle(
                    icon: "sidebar.left",
                    label: "File Tree",
                    isActive: windowState.hasColumn(renderMode: .fileTree)
                ) {
                    appState.toggleColumn(renderMode: .fileTree)
                }
            }

            ToolbarItem(id: "preview", placement: .automatic) {
                toolbarPanelToggle(
                    icon: "doc.text.magnifyingglass",
                    label: "Preview",
                    isActive: windowState.hasColumn(renderMode: .markdownPreview)
                ) {
                    appState.toggleColumn(renderMode: .markdownPreview)
                }
            }

            ToolbarItem(id: "html", placement: .automatic) {
                toolbarPanelToggle(
                    icon: "globe",
                    label: "HTML",
                    isActive: windowState.hasColumn(renderMode: .htmlPreview)
                ) {
                    appState.toggleColumn(renderMode: .htmlPreview)
                }
            }

            ToolbarItem(id: "terminal", placement: .automatic) {
                toolbarPanelToggle(
                    icon: "terminal",
                    label: "Terminal",
                    isActive: windowState.layout.terminalVisible
                ) {
                    appState.toggleTerminal()
                }
            }

            ToolbarItem(id: "settings", placement: .automatic) {
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .help("Open Sputnik Settings")
                .accessibilityLabel("Settings")
            }
        }
        .background {
            WindowProxyView(
                title: windowState.title,
                documentURL: windowState.currentlyOpenFile
            )
        }
        .onChange(of: appState.activeDocumentID) { _, _ in
            guard appState.activeDocumentID != nil else { return }
            Task {
                try? await editorViewModel.openDocument(appState.activeDocument?.url)
                // Apply saved view state (caret + scroll) for the restored document.
                if let docID = appState.activeDocumentID,
                    let state = windowState.documentViewStates[docID.uuidString]
                {
                    editorViewModel.applyViewState(state)
                }
                // Auto-position: move active text editor column adjacent to File Tree
                if let fileType = appState.activeDocument?.fileType,
                    fileType == .text || fileType == .markdown || fileType == .html
                        || fileType == .ascii,
                    let activeColID = windowState.activeColumnID
                {
                    windowState.layout.dynamicLayout.moveActiveEditorAdjacentToFileTree(
                        activeColumnID: activeColID)
                    // Layout is persisted by the next flush cycle from the app delegate.
                }
            }
        }
    }

    // MARK: - Panel content

    /// Returns the appropriate panel module for the given render mode.
    @ViewBuilder
    private func panelContentView(
        renderMode: PanelID,
        documentID: UUID?,
        columnRole: DynamicPanelLayout.ColumnRole
    ) -> some View {
        switch renderMode {
        case .fileTree:
            FileTreePanel(router: router)

        case .textEditor:
            TextEditorPanel(
                viewModel: editorViewModel,
                settings: settings,
                appState: appState,
                isEditable: columnRole == .active
            )

        case .markdownPreview:
            MarkdownPreviewPanel(
                helpContextEnabled: columnRole == .active || columnRole == .activePair
            )

        case .htmlPreview:
            HTMLPreviewPanel(
                router: router,
                helpContextEnabled: columnRole == .active || columnRole == .activePair
            )

        case .pdfViewer:
            PDFViewerPanel()

        case .asciiStudio:
            ASCIIStudioView()

        case .asciiArtHelp, .markdownHelp, .htmlHelp, .grammarHelp:
            // Help panels are rendered via helpPanelOverlay, not as columns.
            EmptyView()
        }
    }

    // MARK: - Toolbar helpers

    /// Builds a unified toolbar toggle button that reflects its active state.
    /// - Parameters:
    ///   - icon: SF Symbol name for the button.
    ///   - label: Human-readable label for accessibility and tooltip.
    ///   - isActive: Whether the associated panel is currently visible.
    ///   - action: Closure to call on tap.
    private func toolbarPanelToggle(
        icon: String,
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .symbolVariant(isActive ? .fill : .none)
        }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Help panel overlay

    /// Overlays the help panels on top of the column area.
    /// All five views stay in the tree so each panel's @State survives topic switches.
    @ViewBuilder
    private var helpPanelOverlay: some View {
        let topic = windowState.requestedHelpTopic
        ZStack {
            // Default content area (visible when no help topic is active)
            // This is intentionally empty — the columns below handle content.
            Color.clear

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
