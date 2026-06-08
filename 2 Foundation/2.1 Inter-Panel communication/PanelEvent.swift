import Foundation

/// Events broadcast through `InterPanelRouter` to coordinate modules without direct coupling.
public enum PanelEvent: Sendable {
    /// A file has been opened; all interested panels should react to its `FileType`.
    case fileOpened(URL, FileType)
    /// The active workspace directory has changed; panels that display a directory path should update.
    case directoryChanged(URL)
}
