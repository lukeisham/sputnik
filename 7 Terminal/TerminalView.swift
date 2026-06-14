import FoundationModule
import SwiftUI

/// The SwiftUI panel view for the terminal module.
///
/// This is the public entry point that Foundation's layout (2.4) drops into the
/// bottom-pinned slot. It composes `TerminalRenderer`, hosts the profile chrome
/// and a multi-tab strip, wires keystroke routing through `KeyEncoder` →
/// `TerminalManager`, and renders disabled/placeholder states on PTY or launch
/// failure via `SputnikAlert`.
///
/// Multi-terminal (Step 9): A tab strip inside the pinned slot lets the user
/// add, switch, and close independent Zsh PTY sessions within one window.
public struct TerminalView: View {

    // MARK: - Environment

    @Environment(WindowState.self) private var windowState
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @Environment(MainAIMonitor.self) private var mainAIMonitor
    @Environment(PanelFocusCoordinator.self) private var focusCoordinator

    /// Drops the chrome's translucency for an opaque surface under *Reduce Transparency*.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Tab model

    private struct TerminalTab: Identifiable {
        let manager: TerminalManager
        var id: UUID { manager.id }
    }

    // MARK: - State

    @State private var tabs: [TerminalTab] = []
    @State private var activeTabID: UUID?
    @State private var showAlert: Bool = false
    @State private var tabCounter: Int = 0
    /// Guards against spawning more than one initial Zsh session. Set on first spawn;
    /// prevents repeated `onAppear` calls (and visibility-on/off cycles) from forking
    /// additional PTYs. The user can still add tabs manually via the "+" button.
    @State private var hasLaunched = false

    // MARK: - Computed

    private var activeTab: TerminalTab? {
        tabs.first { $0.id == activeTabID }
    }

    private var activeManager: TerminalManager? {
        activeTab?.manager
    }

    private var profile: TerminalProfile {
        TerminalProfile(
            fontName: settings.terminalFontName,
            fontSize: settings.terminalFontSize,
            foreground: settings.terminalForeground,
            background: settings.terminalBackground,
            scrollbackLineLimit: settings.terminalScrollbackLimit
        )
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            profileChrome
            tabStrip
            terminalBody
        }
        .background(profile.swiftUIBackground)
        .overlay { focusIndicator }
        .onAppear {
            // Defer PTY spawn until the terminal strip is actually visible. This keeps
            // the forkpty launch off the critical launch path (ISS-107).
            guard !hasLaunched, windowState.layout.terminalVisible else { return }
            hasLaunched = true
            if tabs.isEmpty { addTab() }
        }
        .onChange(of: windowState.layout.terminalVisible) { _, isVisible in
            // First-show path: TerminalView is always in the hierarchy (confirmed in
            // ContentView), so onAppear fires at launch. If terminalVisible was false
            // at that point the spawn was skipped; trigger it here on first reveal.
            guard isVisible, !hasLaunched else { return }
            hasLaunched = true
            if tabs.isEmpty { addTab() }
        }
        .onChange(of: windowState.activeWorkspaceDirectory) { _, newValue in
            for tab in tabs {
                tab.manager.syncWorkingDirectory(newValue)
            }
        }
        .onChange(of: activeManager?.pendingAlert) { _, alert in
            showAlert = (alert != nil)
        }
        .onChange(of: windowState.newTerminalTabRequested) { _, _ in
            addTab()
        }
        .alert(
            activeManager?.pendingAlert?.title ?? "",
            isPresented: $showAlert,
            actions: {
                Button("Retry") {
                    activeManager?.dismissAlert()
                    Task {
                        await activeManager?.startSession(
                            directory: windowState.activeWorkspaceDirectory)
                    }
                }
                Button("Dismiss", role: .cancel) {
                    activeManager?.dismissAlert()
                }
            },
            message: {
                Text(activeManager?.pendingAlert?.message ?? "")
            }
        )
    }

    // MARK: - Sub-views

    /// Profile label chrome displayed above the tab strip.
    /// Includes a badge pill ("TERM") consistent with column badge styling.
    private var profileChrome: some View {
        HStack {
            // Badge pill consistent with column badges
            Text("TERM")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(SputnikColor.accentPrimary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(SputnikColor.accentPrimary.opacity(0.15))
                .clipShape(Capsule())
                .accessibilityLabel("Panel type: Terminal")

            Text("Terminal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(profile.fontName) \(Int(profile.fontSize))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            shellExitedBadge
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if reduceTransparency {
                SputnikColor.secondaryBackground
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }

    /// Compact tab strip for switching between terminal sessions.
    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    tabButton(for: tab)
                }
                addTabButton
                Spacer(minLength: 0)
            }
        }
        .frame(height: 24)
        .background {
            if reduceTransparency {
                SputnikColor.secondaryBackground.opacity(0.5)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
    }

    /// A single tab in the strip.
    private func tabButton(for tab: TerminalTab) -> some View {
        let isActive = tab.id == activeTabID
        let label = tabLabel(for: tab)
        return HStack(spacing: 4) {
            Button {
                switchToTab(tab)
            } label: {
                Text(label)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 100)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .padding(.vertical, 2)

            Button {
                closeTab(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
            .opacity(tabs.count > 1 ? 1 : 0)  // Hide close button on single tab
        }
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 4)
                    .fill(SputnikColor.secondaryBackground)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
            }
        }
    }

    /// "+" button to add a new terminal tab.
    private var addTabButton: some View {
        Button {
            addTab()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .help("New Terminal Tab")
    }

    /// Returns a display label for a terminal tab.
    private func tabLabel(for tab: TerminalTab) -> String {
        if let title = tab.manager.snapshot?.title, !title.isEmpty {
            return title
        }
        // Use the tab's index for a stable label.
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            return "Terminal \(index + 1)"
        }
        return "Terminal"
    }

    /// Inline "shell exited" notice shown when the active session is not running.
    @ViewBuilder
    private var shellExitedBadge: some View {
        if let mgr = activeManager, !mgr.isRunning && mgr.pendingAlert == nil {
            Button {
                Task { await mgr.startSession(directory: windowState.activeWorkspaceDirectory) }
            } label: {
                Label("Shell exited — restart", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
    }

    /// The renderer or a placeholder when no active tab exists.
    @ViewBuilder
    private var terminalBody: some View {
        if let mgr = activeManager {
            if mgr.pendingAlert != nil {
                // Disabled placeholder while the alert is pending.
                ZStack {
                    profile.swiftUIBackground
                    VStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Terminal unavailable")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                TerminalContent(
                    manager: mgr,
                    profile: profile,
                    workspaceDirectory: windowState.activeWorkspaceDirectory
                )
            }
        } else {
            // No tabs at all — empty restartable state.
            ZStack {
                profile.swiftUIBackground
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No terminal session")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Button("Start Terminal") {
                        addTab()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Focus indicator

    /// A visible focus ring overlay matching the column focus indicator style.
    @ViewBuilder
    private var focusIndicator: some View {
        let isFocused = focusCoordinator.focusedPanel == .terminal
        if isFocused {
            RoundedRectangle(cornerRadius: 2)
                .stroke(
                    SputnikColor.accentPrimary.opacity(0.55),
                    lineWidth: 2
                )
                .padding(1)
                .allowsHitTesting(false)
                .accessibleAnimation(.easeInOut(duration: 0.12), value: isFocused)
        }
    }

    // MARK: - Tab management

    /// Creates a new terminal tab with an independent Zsh PTY session.
    private func addTab() {
        tabCounter += 1
        let manager = TerminalManager()
        manager.aiOutputObserver = mainAIMonitor
        let tab = TerminalTab(manager: manager)
        tabs.append(tab)
        activeTabID = tab.id

        // Register with WindowState for clean shutdown and editor integration.
        windowState.terminalManagers.append(manager)
        windowState.terminalCommander = manager

        // Start the Zsh session.
        Task {
            await manager.startSession(
                directory: windowState.activeWorkspaceDirectory,
                profile: profile
            )
        }
    }

    /// Closes a terminal tab, terminating its PTY session.
    private func closeTab(_ tab: TerminalTab) {
        // Terminate the PTY asynchronously (spec 7.5 — no zombies).
        Task { await tab.manager.stopSession() }

        // Remove from WindowState's lifecycle collection.
        windowState.terminalManagers.removeAll {
            ($0 as AnyObject) === (tab.manager as AnyObject)
        }

        // Remove from the view's tab list.
        tabs.removeAll { $0.id == tab.id }

        // Update the active tab.
        if activeTabID == tab.id {
            if let newActive = tabs.first {
                activeTabID = newActive.id
                windowState.terminalCommander = newActive.manager
            } else {
                activeTabID = nil
                windowState.terminalCommander = nil
            }
        }
    }

    /// Switches the visible terminal to the given tab's session.
    private func switchToTab(_ tab: TerminalTab) {
        activeTabID = tab.id
        windowState.terminalCommander = tab.manager
    }

    // MARK: - Init

    public init() {}
}

// MARK: - TerminalContent

/// Inner view that properly `@ObservedObject`-observes the active `TerminalManager` so
/// that `@Published` changes (snapshot, sessionEndedMessage, isRunning) immediately
/// drive re-renders without requiring the outer `TerminalView` to hold the manager as
/// an `@StateObject`. Owns the `TerminalRenderer` + dead-session banner overlay.
private struct TerminalContent: View {

    @ObservedObject var manager: TerminalManager
    let profile: TerminalProfile
    let workspaceDirectory: URL?

    var body: some View {
        TerminalRenderer(
            snapshot: manager.snapshot,
            profile: profile,
            onKeyInput: { data in
                // When the session has ended, swallow all keystrokes and restart on Return.
                guard manager.sessionEndedMessage == nil else {
                    if data.count == 1, data[0] == 0x0D {
                        Task {
                            await manager.startSession(
                                directory: workspaceDirectory,
                                profile: profile
                            )
                        }
                    }
                    return
                }
                manager.send(data)
            },
            onResize: { cols, rows in
                manager.resize(cols: cols, rows: rows)
            },
            onTextViewCreated: { textView in
                manager.terminalTextView = textView
            }
        )
        .overlay {
            if let message = manager.sessionEndedMessage {
                deadSessionBanner(message: message)
            }
        }
    }

    private func deadSessionBanner(message: String) -> some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 10) {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Button("Restart") {
                    Task {
                        await manager.startSession(
                            directory: workspaceDirectory,
                            profile: profile
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
