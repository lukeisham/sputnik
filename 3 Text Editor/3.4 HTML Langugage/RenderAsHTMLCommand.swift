import AppKit

/// Handles the "Render as HTML" command (⌘⌥P, File menu).
///
/// Enabled only when `EditorViewModel.htmlModeActive` is `true`.
/// Routes to the HTML Preview panel (module 8) via the Foundation 2.1
/// `InterPanelRouter` protocol — the editor never calls module 8 directly (SR-1, SC-9).
@MainActor
public final class RenderAsHTMLCommand {

    // MARK: - Dependencies

    private weak var viewModel: EditorViewModel?
    private weak var router: (any InterPanelRouter)?

    public init(viewModel: EditorViewModel, router: any InterPanelRouter) {
        self.viewModel = viewModel
        self.router    = router
    }

    // MARK: - Action

    /// Executes the "Render as HTML" command.
    ///
    /// Opens or brings to front the HTML Preview panel via the router. No-op if
    /// HTML mode is inactive or the current file has no URL yet.
    public func execute() async {
        guard let viewModel, viewModel.htmlModeActive,
              let url = viewModel.fileURL
        else { return }
        await router?.open(url)
    }

    // MARK: - Validation

    /// Returns `true` when the menu item should be enabled.
    ///
    /// Wire into `NSMenuItem.validate(_:)` or `NSMenuItemValidation`.
    public func isEnabled() -> Bool {
        viewModel?.htmlModeActive == true && viewModel?.fileURL != nil
    }
}
