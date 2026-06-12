import FoundationModule
import ResourcesModule
import SwiftUI

/// Top-level SwiftUI view for the Markdown Preview panel.
///
/// Assembles the header bar (document title + overflow menu), toolbar (Fit Width,
/// Font Size, Link toggle), and the `MarkdownRenderView` content area. Observes
/// `AppState.activeDocument` via `@Environment` and drives the render pipeline
/// through `MarkdownPreviewViewModel`.
///
/// **State-driven content:**
/// - Active + `.markdown` → renders the Markdown via `MarkdownRenderView`.
/// - Active + not `.markdown` → shows a placeholder with the active filename.
/// - No active document → shows an empty-state placeholder.
/// - Render error → subtle warning banner + plain-text fallback already rendered.
///
/// **Layout:** Occupies the `centerLower` slot by default.
public struct MarkdownPreviewPanel: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    // MARK: - State

    @State private var viewModel = MarkdownPreviewViewModel()
    @State private var fitWidth: Bool = true
    @State private var linksEnabled: Bool = true
    /// Per-document scroll positions, keyed by `DocumentSession.id`.
    /// Written by `MarkdownRenderView`'s scroll observer; read back on document switch.
    @State private var scrollOffsets: [UUID: CGFloat] = [:]

    /// The coordinator for this panel, created once on init and wired into `MarkdownRenderView`.
    private let coordinator: MarkdownPreviewCoordinator

    /// The help-context resolver used for the "More Context" right-click gesture.
    private let helpContextResolver: HelpContextResolving

    /// Whether help-context actions are enabled for this panel instance.
    /// `true` for `.active` and `.activePair` columns, `false` for `.viewOnly`.
    private var helpContextEnabled: Bool = true

    // MARK: - Init

    /// Creates the Markdown Preview panel.
    /// - Parameters:
    ///   - router:                The app's `InterPanelRouter` instance. `nil` disables
    ///                            tab-open behaviour for link clicks (preview becomes read-only).
    ///   - helpContextResolver:   The resolver for right-click "More Context" help.
    ///                            Defaults to `SputnikHelpContextResolver.shared`.
    ///   - helpContextEnabled:    Whether help-context actions are enabled. `true` for active
    ///                            and active-pair columns, `false` for view-only. Defaults to `true`.
    @MainActor
    public init(
        router: (any InterPanelRouter)? = nil,
        helpContextResolver: HelpContextResolving? = nil,
        helpContextEnabled: Bool = true
    ) {
        self.coordinator = MarkdownPreviewCoordinator(router: router)
        self.helpContextResolver = helpContextResolver ?? SputnikHelpContextResolver.shared
        self.helpContextEnabled = helpContextEnabled
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            toolbar
            Divider()
            contentArea
        }
        .background(SputnikColor.editorBackground)
        .task {
            viewModel.configure(appState: appState)
            coordinator.helpContextResolver = helpContextResolver
            coordinator.onRequestHelp = { [weak appState] request in
                appState?.requestedHelpTarget = request
            }
        }
        .onChange(of: appState.activeDocument?.text ?? "") { _, newValue in
            triggerRender(markdown: newValue)
        }
        .onChange(of: appState.activeDocumentID) { _, _ in
            handleActiveDocumentChange()
        }
        .onAppear {
            handleActiveDocumentChange()
        }
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(spacing: SputnikSpacing.sm) {
            // Panel title + current document filename.
            Text("MARKDOWN PREVIEW")
                .font(.system(size: SputnikFont.caption, weight: .semibold, design: .default))
                .foregroundStyle(SputnikColor.secondaryText)

            if let name = appState.activeDocument?.url?.lastPathComponent {
                Text("—")
                    .foregroundStyle(SputnikColor.tertiaryText)
                Text(name)
                    .font(.system(size: SputnikFont.caption, weight: .medium, design: .default))
                    .foregroundStyle(SputnikColor.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Overflow menu: Reveal in Finder.
            Menu {
                if let url = appState.activeDocument?.url {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } else {
                    Text("No file to reveal")
                        .foregroundStyle(SputnikColor.tertiaryText)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: SputnikFont.caption))
                    .foregroundStyle(SputnikColor.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24, height: 24)
            .disabled(appState.activeDocument?.url == nil)
            .accessibilityLabel("More actions")
        }
        .padding(.horizontal, SputnikSpacing.md)
        .padding(.vertical, SputnikSpacing.sm)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: SputnikSpacing.xs) {
            // Fit Width toggle.
            Button {
                fitWidth.toggle()
            } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .font(.system(size: SputnikFont.caption))
            }
            .help("Fit Width")
            .buttonStyle(.borderless)
            .foregroundStyle(fitWidth ? SputnikColor.accent : SputnikColor.secondaryText)
            .accessibilityLabel("Fit width")
            .accessibilityAddTraits(fitWidth ? .isSelected : [])

            // Font Size cycle button.
            Menu {
                ForEach([0.8, 1.0, 1.2, 1.5], id: \.self) { scale in
                    Button {
                        viewModel.fontScale = CGFloat(scale)
                    } label: {
                        HStack {
                            Text("\(Int(scale * 100))%")
                            if viewModel.fontScale == CGFloat(scale) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: SputnikFont.caption))
            }
            .help("Font Size")
            .buttonStyle(.borderless)
            .foregroundStyle(SputnikColor.secondaryText)
            .menuIndicator(.hidden)
            .accessibilityLabel("Font size")
            .accessibilityValue("\(Int(viewModel.fontScale * 100)) percent")

            // Link toggle.
            Button {
                linksEnabled.toggle()
                coordinator.linksEnabled = linksEnabled
            } label: {
                Image(systemName: "link")
                    .font(.system(size: SputnikFont.caption))
            }
            .help(linksEnabled ? "Links Enabled" : "Links Disabled")
            .buttonStyle(.borderless)
            .foregroundStyle(linksEnabled ? SputnikColor.accent : SputnikColor.tertiaryText)
            .accessibilityLabel("Links")
            .accessibilityValue(linksEnabled ? "Enabled" : "Disabled")

            Spacer()
        }
        .padding(.horizontal, SputnikSpacing.md)
        .padding(.vertical, SputnikSpacing.xs)
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        let session = appState.activeDocument

        if let session {
            if session.fileType == .markdown || session.fileType == .ascii {
                // Render error banner.
                if let error = viewModel.renderError {
                    errorBanner(error)
                }

                // Wrapping text view with width layout.
                if fitWidth {
                    ScrollView(.vertical) {
                        MarkdownRenderView(
                            renderedString: viewModel.renderedString,
                            fontScale: viewModel.fontScale,
                            coordinator: coordinator,
                            settings: settings,
                            scrollOffset: scrollBinding(for: appState.activeDocumentID)
                        )
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ScrollView(.vertical) {
                        MarkdownRenderView(
                            renderedString: viewModel.renderedString,
                            fontScale: viewModel.fontScale,
                            coordinator: coordinator,
                            settings: settings,
                            scrollOffset: scrollBinding(for: appState.activeDocumentID)
                        )
                    }
                }
            } else {
                // Active document is not Markdown — show placeholder.
                notMarkdownPlaceholder(session: session)
            }
        } else {
            // No active document.
            emptyStatePlaceholder
        }
    }

    // MARK: - Placeholders

    private func notMarkdownPlaceholder(session: DocumentSession) -> some View {
        VStack(spacing: SputnikSpacing.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(SputnikColor.tertiaryText)
            let message =
                session.fileType == .ascii
                ? "ASCII file selected — open a Markdown file to preview"
                : "Plain text file selected — open a Markdown file to preview"
            Text(message)
                .font(.system(size: SputnikFont.body, weight: .medium))
                .foregroundStyle(SputnikColor.secondaryText)
            if let name = session.url?.lastPathComponent {
                Text("\"\(name)\" is a \(session.fileType.rawValue) file.")
                    .font(.system(size: SputnikFont.caption))
                    .foregroundStyle(SputnikColor.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStatePlaceholder: some View {
        VStack(spacing: SputnikSpacing.sm) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 32))
                .foregroundStyle(SputnikColor.tertiaryText)
            Text("No file open")
                .font(.system(size: SputnikFont.body, weight: .medium))
                .foregroundStyle(SputnikColor.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: SputnikSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: SputnikFont.caption))
                .foregroundStyle(Color.yellow)
            Text("Parse warning: \(message)")
                .font(.system(size: SputnikFont.caption))
                .foregroundStyle(SputnikColor.secondaryText)
            Spacer()
        }
        .padding(.horizontal, SputnikSpacing.md)
        .padding(.vertical, SputnikSpacing.xs)
        .background(Color.yellow.opacity(0.10))
    }

    // MARK: - Scroll binding

    /// Returns a `Binding<CGFloat>` that reads and writes `scrollOffsets[id]`.
    /// Used to give `MarkdownRenderView` a stable per-document scroll slot.
    private func scrollBinding(for id: UUID?) -> Binding<CGFloat> {
        guard let id else { return .constant(0) }
        return Binding(
            get: { scrollOffsets[id, default: 0] },
            set: { scrollOffsets[id] = $0 }
        )
    }

    // MARK: - Render trigger

    /// Initiates a Markdown render when the active session's text changes.
    private func triggerRender(markdown: String) {
        guard let session = appState.activeDocument,
            session.fileType == .markdown || session.fileType == .ascii
        else { return }
        viewModel.render(markdown: markdown, fontScale: viewModel.fontScale)
    }

    /// Handles a change in the active document — clears stale state and triggers
    /// a render if the new session is Markdown.
    private func handleActiveDocumentChange() {
        // Restore the saved scroll offset for the incoming document so that
        // MarkdownRenderView can use it when the render lands.
        viewModel.scrollOffset = scrollOffsets[appState.activeDocumentID ?? UUID(), default: 0]

        guard let session = appState.activeDocument else {
            viewModel.renderedString = NSAttributedString()
            viewModel.renderError = nil
            return
        }

        if session.fileType == .markdown || session.fileType == .ascii {
            viewModel.render(markdown: session.text, fontScale: viewModel.fontScale)
        } else {
            viewModel.renderedString = NSAttributedString()
            viewModel.renderError = nil
        }
    }
}
