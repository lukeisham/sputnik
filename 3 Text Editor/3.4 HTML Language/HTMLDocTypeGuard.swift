import Foundation

/// Scans the first ~512 characters of a file for `<!DOCTYPE html>` and sets
/// `EditorViewModel.htmlModeActive` accordingly.
///
/// The 512-character cap bounds scan time even on very large files (SR-3, SR-4).
/// Re-runs at file open and on each full document reload.
/// Result sets `EditorViewModel.htmlModeActive` (SC-10).
public enum HTMLDocTypeGuard {

    // MARK: - Check

    /// Inspects `content` and updates `viewModel.htmlModeActive`.
    ///
    /// Only the leading 512 characters are examined; the rest of the file is ignored.
    /// The check is case-insensitive (`<!DOCTYPE HTML>` and `<!doctype html>` both match).
    ///
    /// - Parameters:
    ///   - content:   The full file text (only the prefix is read).
    ///   - viewModel: The `EditorViewModel` whose `htmlModeActive` flag is updated.
    @MainActor
    public static func check(_ content: String, viewModel: EditorViewModel) {
        let sample = content.prefix(512).lowercased()
        viewModel.htmlModeActive = sample.contains("<!doctype html")
    }
}
