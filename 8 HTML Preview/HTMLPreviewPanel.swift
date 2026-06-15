import FoundationModule
import Observation
import ResourcesModule
import SwiftUI

/// Top-level SwiftUI view for the HTML Preview panel.
///
/// Assembles the header bar (document title + overflow menu), toolbar (Fit Width +
/// Link Navigation toggle), and the existing `HTMLPreviewView` content area. Observes
/// `AppState.activeDocument` via `@Environment` and switches between three display
/// states: rendering (`.html` active), wrong-type placeholder (non-`.html` active),
/// and empty-state placeholder (no document open).
///
/// **Layout:** Appears as a column in the dynamic layout.
public struct HTMLPreviewPanel: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    // MARK: - State

    @State private var isFitWidth: Bool = true
    @State private var isLinkNavigationEnabled: Bool = true
    @State private var syncScrollEnabled: Bool = false
    @State private var loadError: String? = nil

    /// `true` when the active HTML document exceeds the large-file threshold (Step 10).
    /// Disables scroll sync to prevent layout thrash on very large files.
    private var isLargeFile: Bool {
        (appState.activeDocument?.text.utf16.count ?? 0) >= 80_000
    }

    // MARK: - Dependencies

    /// The app's inter-panel router, passed through to `HTMLPreviewView`.
    private let router: (any InterPanelRouter)?

    /// The coordinator for this panel, created once on init and injected into
    /// `HTMLPreviewView`. The print / save-as-PDF / save-as-HTML actions live on it
    /// (ISS-095), wired once in `HTMLPreviewView.makeNSView` and read here directly.
    private let coordinator: HTMLPreviewCoordinator

    /// The shared help-context resolver, passed through to `HTMLPreviewView`.
    private let helpContextResolver: HelpContextResolving

    /// Whether help-context actions are enabled for this panel instance.
    /// `true` for `.active` and `.activePair` columns, `false` for `.viewOnly`.
    private var helpContextEnabled: Bool = true

    // MARK: - Init

    /// Creates the HTML Preview panel.
    /// - Parameters:
    ///   - router:                The app's `InterPanelRouter` instance. `nil` disables
    ///                            tab-open behaviour for link clicks (preview becomes read-only).
    ///   - helpContextResolver:   Resolver for "More Context" right-click help. Defaults to
    ///                            `SputnikHelpContextResolver.shared`.
    ///   - helpContextEnabled:    Whether help-context actions are enabled. `true` for active
    ///                            and active-pair columns, `false` for view-only. Defaults to `true`.
    @MainActor
    public init(
        router: (any InterPanelRouter)? = nil,
        helpContextResolver: HelpContextResolving? = nil,
        helpContextEnabled: Bool = true
    ) {
        self.router = router
        self.coordinator = HTMLPreviewCoordinator(router: router)
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
        .overlay(alignment: .trailing) {
            Minimap()
        }
        .background(SputnikColor.editorBackground)
        .onChange(of: appState.activeDocumentID) { _, _ in
            loadError = nil
            updatePairedPreviewActions()
        }
        .onAppear {
            updatePairedPreviewActions()
        }
        .onDisappear {
            appState.pairedPreviewPrintAction = nil
            appState.pairedPreviewSaveAsPDFAction = nil
            appState.activeWindow?.minimapTargetWebView = nil
        }
    }

    // MARK: - Paired preview action registration

    /// Writes the panel's print and save-as-PDF closures into `AppState` when an HTML
    /// document is active, so the editor overflow menu and File menu can offer a
    /// "Plain Text / Rendered" choice. Clears both fields otherwise.
    private func updatePairedPreviewActions() {
        guard let session = appState.activeDocument, session.fileType == .html else {
            // JSON and all other types have no paired print/PDF actions.
            appState.pairedPreviewPrintAction = nil
            appState.pairedPreviewSaveAsPDFAction = nil
            return
        }
        // Delegate into the coordinator's actions, read live at invocation time. Safe to
        // register before `HTMLPreviewView.makeNSView` wires them — a tap before the view
        // exists is a harmless no-op (ISS-095).
        appState.pairedPreviewPrintAction = { [weak coordinator] in coordinator?.printAction?() }
        appState.pairedPreviewSaveAsPDFAction = { [weak coordinator] in
            coordinator?.saveAsPDFAction?()
        }
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(spacing: SputnikSpacing.sm) {
            Text("HTML PREVIEW")
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
            } else if appState.activeDocument != nil {
                Text("— Untitled")
                    .font(.system(size: SputnikFont.caption, weight: .medium, design: .default))
                    .foregroundStyle(SputnikColor.tertiaryText)
            }

            Spacer()

            // Overflow menu: Save as HTML…, Save as PDF…, Print…, Reveal in Finder, Reload Preview.
            Menu {
                Button("Save as HTML…") { coordinator.saveAsHTMLAction?() }
                    .disabled(appState.activeDocument?.fileType != .html)

                Button("Save as PDF…") { coordinator.saveAsPDFAction?() }
                    .disabled(appState.activeDocument?.fileType != .html)

                Button("Print…") { coordinator.printAction?() }
                    .disabled(appState.activeDocument?.fileType != .html)

                Divider()

                if let url = appState.activeDocument?.url {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Button("Reload Preview") {
                    loadError = nil
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: SputnikFont.caption))
                    .foregroundStyle(SputnikColor.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24, height: 24)
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
                isFitWidth.toggle()
            } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .font(.system(size: SputnikFont.caption))
            }
            .help("Fit Width")
            .buttonStyle(.borderless)
            .foregroundStyle(isFitWidth ? SputnikColor.accent : SputnikColor.secondaryText)
            .accessibilityLabel("Fit width")
            .accessibilityAddTraits(isFitWidth ? .isSelected : [])

            // Link Navigation toggle.
            Button {
                isLinkNavigationEnabled.toggle()
            } label: {
                Image(systemName: "link")
                    .font(.system(size: SputnikFont.caption))
            }
            .help(isLinkNavigationEnabled ? "Links Enabled" : "Links Disabled")
            .accessibilityLabel("Links")
            .accessibilityValue(isLinkNavigationEnabled ? "Enabled" : "Disabled")
            .buttonStyle(.borderless)
            .foregroundStyle(
                isLinkNavigationEnabled ? SputnikColor.accent : SputnikColor.tertiaryText)

            // Scroll sync toggle (ISS-063, Steps 3 & 5).
            Button {
                syncScrollEnabled.toggle()
            } label: {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(.system(size: SputnikFont.caption))
            }
            .help(syncScrollEnabled ? "Scroll Sync On" : "Scroll Sync Off")
            .buttonStyle(.borderless)
            .foregroundStyle(
                syncScrollEnabled && !isLargeFile
                    ? SputnikColor.accent : SputnikColor.secondaryText
            )
            .disabled(isLargeFile)
            .accessibilityLabel("Scroll sync")
            .accessibilityValue(syncScrollEnabled ? "On" : "Off")

            // Large-file degraded-mode indicator (Step 10).
            if isLargeFile {
                Text("Large file — sync limited")
                    .font(.system(size: SputnikFont.caption))
                    .foregroundStyle(SputnikColor.tertiaryText)
            }

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
            if session.fileType == .json {
                JSONViewerPanel()
            } else if session.fileType == .html {
                // Error banner above the web view.
                if let error = loadError {
                    errorBanner(error)
                }

                HTMLPreviewView(
                    isLinkNavigationEnabled: isLinkNavigationEnabled,
                    syncScrollEnabled: syncScrollEnabled && !isLargeFile,
                    onLoadError: { message in loadError = message },
                    helpContextResolver: helpContextResolver,
                    settings: settings,
                    coordinator: coordinator
                )
                // Fit Width: centre the preview with a max width of 960 pt.
                // When disabled, the web view fills the entire panel width.
                .frame(maxWidth: isFitWidth ? 960 : .infinity)
            } else {
                notHTMLPlaceholder(session: session)
            }
        } else {
            emptyStatePlaceholder
        }
    }

    // MARK: - Placeholders

    private func notHTMLPlaceholder(session: DocumentSession) -> some View {
        VStack(spacing: SputnikSpacing.sm) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(SputnikColor.tertiaryText)
            Text("No HTML file open")
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
            Image(systemName: "globe")
                .font(.system(size: 32))
                .foregroundStyle(SputnikColor.tertiaryText)
            Text("Open an HTML file to preview")
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
            Text("Load error: \(message)")
                .font(.system(size: SputnikFont.caption))
                .foregroundStyle(SputnikColor.secondaryText)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, SputnikSpacing.md)
        .padding(.vertical, SputnikSpacing.xs)
        .background(Color.yellow.opacity(0.10))
    }
}
