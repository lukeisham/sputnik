import Foundation

extension AppState {

    // MARK: - Window registry

    /// The frontmost window's state. `nil` only if no windows exist yet.
    public var activeWindow: WindowState? {
        guard let id = activeWindowID else { return orderedWindowIDs.first.flatMap { windows[$0] } }
        return windows[id]
    }

    // MARK: - Window lifecycle

    /// Creates a new `WindowState`, registers it, and makes it the active window.
    @discardableResult
    public func createWindow() -> WindowState {
        let w = WindowState()
        windows[w.id] = w
        orderedWindowIDs.append(w.id)
        activeWindowID = w.id
        return w
    }

    /// Removes a window from the registry and selects a new active window if needed.
    /// Callers must have already killed the window's terminal and confirmed any dirty tabs.
    public func closeWindow(_ id: UUID) {
        windows.removeValue(forKey: id)
        orderedWindowIDs.removeAll { $0 == id }
        if activeWindowID == id {
            activeWindowID = orderedWindowIDs.last
        }
    }

    /// Returns the `WindowState` for `id`, or `nil` if it no longer exists.
    public func windowForID(_ id: UUID) -> WindowState? {
        windows[id]
    }

    /// Called by the frontmost-window tracker (via `@FocusedValue`) when the key
    /// window changes.
    public func setActiveWindow(_ id: UUID) {
        guard windows[id] != nil else { return }
        activeWindowID = id
    }
}
