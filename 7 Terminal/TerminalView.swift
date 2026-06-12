import FoundationModule
import SwiftUI

/// The SwiftUI panel view for the terminal module.
///
/// This is the public entry point that Foundation's layout (2.4) drops into the
/// bottom-pinned slot. It composes `TerminalRenderer`, hosts the profile chrome,
/// wires keystroke routing through `KeyEncoder` → `TerminalManager`, and
/// renders disabled/placeholder states on PTY or launch failure via `SputnikAlert`.
public struct TerminalView: View {

    // MARK: - Environment

    @Environment(WindowState.self) private var windowState
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @Environment(MainAIMonitor.self) private var mainAIMonitor
    @Environment(PanelFocusCoordinator.self) private var focusCoordinator

    /// Drops the chrome's translucency for an opaque surface under *Reduce Transparency*.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - State

    @StateObject private var manager = TerminalManager()
    @State private var showAlert: Bool = false

    // MARK: - Computed profile

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
            terminalBody
        }
        .background(profile.swiftUIBackground)
        .overlay { focusIndicator }
        .onAppear {
            manager.aiOutputObserver = mainAIMonitor
            // Register this TerminalManager on the per-window state so AppDelegate
            // can collect all managers for clean shutdown.
            windowState.terminalManager = manager
        }
        .task {
            await manager.startSession(
                directory: windowState.activeWorkspaceDirectory, profile: profile)
        }
        .onChange(of: windowState.activeWorkspaceDirectory) { _, newValue in
            manager.syncWorkingDirectory(newValue)
        }
        .onChange(of: manager.pendingAlert) { _, alert in
            showAlert = (alert != nil)
        }
        .alert(
            manager.pendingAlert?.title ?? "",
            isPresented: $showAlert,
            actions: {
                Button("Retry") {
                    manager.dismissAlert()
                    Task {
                        await manager.startSession(directory: windowState.activeWorkspaceDirectory)
                    }
                }
                Button("Dismiss", role: .cancel) { manager.dismissAlert() }
            },
            message: {
                Text(manager.pendingAlert?.message ?? "")
            }
        )
    }

    // MARK: - Sub-views

    /// Profile label chrome displayed above the terminal surface.
    private var profileChrome: some View {
        HStack {
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

    /// Inline "shell exited" notice shown when the session is not running.
    @ViewBuilder
    private var shellExitedBadge: some View {
        if !manager.isRunning && manager.pendingAlert == nil {
            Button {
                Task { await manager.startSession(directory: windowState.activeWorkspaceDirectory) }
            } label: {
                Label("Shell exited — restart", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
    }

    /// The renderer or a placeholder when no snapshot is available.
    @ViewBuilder
    private var terminalBody: some View {
        if manager.pendingAlert != nil {
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
            TerminalRenderer(
                snapshot: manager.snapshot,
                profile: profile,
                onKeyInput: { data in manager.send(data) },
                onResize: { cols, rows in manager.resize(cols: cols, rows: rows) }
            )
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

    // MARK: - Init

    public init() {}
}
