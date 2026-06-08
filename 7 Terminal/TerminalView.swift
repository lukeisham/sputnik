import SwiftUI

/// The SwiftUI panel view for the terminal module.
///
/// This is the public entry point that Foundation's layout (2.4) drops into the
/// bottom-pinned slot. It composes `TerminalRenderer`, hosts the profile chrome,
/// wires keystroke routing through `KeyEncoder` → `TerminalManager`, and
/// renders disabled/placeholder states on PTY or launch failure via `SputnikAlert`.
///
/// **ISS-002:** `TerminalProfile` is loaded from a local default because
/// `SettingsStore` (2.3) does not yet expose terminal fields. When 2.3 is updated,
/// replace `TerminalProfile.default` with a property read from
/// `@Environment(SettingsStore.self)`.
public struct TerminalView: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState

    // MARK: - State

    @StateObject private var manager = TerminalManager()

    // ISS-002: local default until SettingsStore (2.3) exposes terminal fields.
    @State private var profile: TerminalProfile = .default

    @State private var showAlert: Bool = false

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            profileChrome
            terminalBody
        }
        .background(profile.swiftUIBackground)
        .task {
            await manager.startSession(directory: appState.activeWorkspaceDirectory)
        }
        .onChange(of: appState.activeWorkspaceDirectory) { _, newValue in
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
                    Task { await manager.startSession(directory: appState.activeWorkspaceDirectory) }
                }
                Button("Dismiss", role: .cancel) { manager.dismissAlert() }
            },
            message: {
                Text(manager.pendingAlert?.message ?? "")
            }
        )
    }

    // MARK: - Sub-views

    /// Profile selector chrome displayed above the terminal surface.
    private var profileChrome: some View {
        HStack {
            Text("Terminal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("Default") { profile = .default }
            } label: {
                HStack(spacing: 4) {
                    Text("Profile: Default")
                        .font(.system(size: 11))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            shellExitedBadge
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    /// Inline "shell exited" notice shown when the session is not running.
    @ViewBuilder
    private var shellExitedBadge: some View {
        if !manager.isRunning && manager.pendingAlert == nil {
            Button {
                Task { await manager.startSession(directory: appState.activeWorkspaceDirectory) }
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
                snapshot:   manager.snapshot,
                profile:    profile,
                onKeyInput: { data in manager.send(data) },
                onResize:   { cols, rows in manager.resize(cols: cols, rows: rows) }
            )
        }
    }

    // MARK: - Init

    public init() {}
}
