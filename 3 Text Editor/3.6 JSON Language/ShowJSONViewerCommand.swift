import AppKit
import FoundationModule

/// Handles the "Render as JSON" command (⌃⌘J, Edit > Render as...).
///
/// Enabled only when `EditorViewModel.jsonModeActive` is `true`.
/// Routes to the JSON viewer panel (module 8 JSON branch) via the Foundation 2.1
/// `InterPanelRouter` protocol — the editor never calls module 8 directly (SR-1).
/// Mirrors `RenderAsHTMLCommand` in 3.4.
@MainActor
public final class ShowJSONViewerCommand {

    // MARK: - Dependencies

    private weak var viewModel: EditorViewModel?
    private weak var router: (any InterPanelRouter)?

    public init(viewModel: EditorViewModel, router: any InterPanelRouter) {
        self.viewModel = viewModel
        self.router = router
    }

    // MARK: - Action

    /// Executes the "Render as JSON" command.
    ///
    /// Opens or brings to front the JSON viewer panel via the router. No-op if
    /// JSON mode is inactive or the current file has no URL yet.
    public func execute() async {
        guard let viewModel, viewModel.jsonModeActive,
            let url = viewModel.fileURL
        else { return }
        await router?.open(url)
    }

    // MARK: - Validation

    /// Returns `true` when the menu item should be enabled.
    ///
    /// Wire into `NSMenuItem.validate(_:)` or `NSMenuItemValidation`.
    public func isEnabled() -> Bool {
        viewModel?.jsonModeActive == true && viewModel?.fileURL != nil
    }
}
