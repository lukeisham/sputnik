import Foundation
import Observation

/// The single, thread-safe source of truth for the app's active workspace and open file.
///
/// Created once in `SputnikApp` and injected into the view hierarchy via `.environment(appState)`.
/// All modules read from it through `@Environment`; the **only writer** is `InterPanelRouter`
/// (module 2.1). Other modules must never mutate `AppState` directly.
///
/// Background file-system events (e.g. from `NSFilePresenter`) **must** hop to `@MainActor`
/// before mutating any property — `@MainActor` isolation makes this a compile-time guarantee.
@Observable
@MainActor
public final class AppState {

    /// The folder currently shown in the File Tree and used as the terminal working directory.
    /// `nil` until the user opens a project folder.
    public var activeWorkspaceDirectory: URL?

    /// The file currently loaded in the active editor or viewer panel.
    /// `nil` until a file is opened.
    public var currentlyOpenFile: URL?

    /// The type of `currentlyOpenFile`, used by panels to decide whether to show themselves.
    /// Defaults to `.unknown` when no file is open.
    public var currentlyOpenFileType: FileType = .unknown

    /// The user's current focus mode; written by the toolbar, read by each panel.
    public var focusMode: FocusMode = .dev

    public init() {}
}
