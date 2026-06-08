import Foundation

/// Gates spell and grammar checking to natural-language file types (.txt, .md).
///
/// Sets `EditorViewModel.spellCheckActive` once at file open.
/// All other file types (.html, binary, etc.) leave the checker disabled.
public enum SpellCheckFileTypeGuard {

    private static let allowedExtensions: Set<String> = ["txt", "md"]

    // MARK: - Check

    /// Inspects the extension of `url` and updates `viewModel.spellCheckActive`.
    ///
    /// - Parameters:
    ///   - url:       The file being opened.
    ///   - viewModel: The `EditorViewModel` whose `spellCheckActive` flag is updated.
    @MainActor
    public static func check(_ url: URL, viewModel: EditorViewModel) {
        let ext = url.pathExtension.lowercased()
        viewModel.spellCheckActive = allowedExtensions.contains(ext)
    }
}
