import FoundationModule
import SwiftUI

/// An invisible view placed inside the first window's hierarchy that opens any
/// additional restored windows (beyond the first) via SwiftUI's `openWindow`
/// environment action.
///
/// Uses a static flag so the restoration fires only once in the app's lifetime,
/// preventing re-entrant window opening when the newly opened windows themselves
/// render this view.
struct WindowRestorerView: View {

    @Environment(\.openWindow) private var openWindow
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                await openPendingWindows()
            }
    }

    /// Consumes `appState.pendingWindowIDs` and opens each via `openWindow`.
    /// Guarded by a static flag to run exactly once.
    private func openPendingWindows() async {
        guard !Self.hasRestored else { return }
        Self.hasRestored = true

        let pending = appState.pendingWindowIDs
        guard !pending.isEmpty else { return }

        // Clear immediately so no other view attempts to re-open.
        appState.pendingWindowIDs.removeAll()

        // Small delay to let the first window's scene fully settle before
        // requesting new scene instances.
        try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 s

        for id in pending {
            openWindow(id: "main", value: id)
        }
    }

    private static var hasRestored = false
}
