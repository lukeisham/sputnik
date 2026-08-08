import Foundation

/// Thin pass-throughs to the active window's scratchpad and minimap state.
/// Grouped here (rather than extracted into a dedicated type) because each accessor is a
/// direct delegation to `WindowState`; the boundary is the marker, not a new owner type.
extension AppState {

    // MARK: - Scratchpad

    public var scratchpadVisible: Bool {
        get { activeWindow?.scratchpadVisible ?? false }
        set { activeWindow?.scratchpadVisible = newValue }
    }

    public var scratchpadText: String {
        get { activeWindow?.scratchpadText ?? "" }
        set { activeWindow?.scratchpadText = newValue }
    }

    public var scratchpadDockedWidth: CGFloat {
        get { activeWindow?.scratchpadDockedWidth ?? 280 }
        set { activeWindow?.scratchpadDockedWidth = newValue }
    }

    // MARK: - Minimap

    public var minimapVisible: Bool {
        get { activeWindow?.minimapVisible ?? false }
        set { activeWindow?.minimapVisible = newValue }
    }

    /// Toggles the minimap for the active window.
    public func toggleMinimap() {
        activeWindow?.minimapVisible.toggle()
    }
}
