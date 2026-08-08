import Foundation

extension AppState {

    // MARK: - Processing state

    /// `true` if *any* open window is currently processing AI work.
    /// Used by `SputnikMenuBarController` (the menu-bar icon is global).
    public var isProcessing: Bool {
        windows.values.contains { $0.isProcessing }
    }

    public func beginProcessing() { activeWindow?.beginProcessing() }
    public func endProcessing() { activeWindow?.endProcessing() }

    // MARK: - AI state

    /// Delegates to the active window for Main AI state.
    public var mainAIState: MainAIState? {
        get { activeWindow?.mainAIState }
        set { activeWindow?.mainAIState = newValue }
    }
}
