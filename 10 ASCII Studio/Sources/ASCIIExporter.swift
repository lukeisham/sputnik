import AppKit
import Foundation
import UniformTypeIdentifiers

/// Handles opening and saving `.txt` ASCII art files.
///
/// - **Save as `.txt`:** retains the source image's filename (no stored back-reference).
/// - **Open `.txt`:** loads an existing ASCII text file for editing.
///
/// All panel operations are on `@MainActor`.
public enum ASCIIExporter {

    // MARK: - Save

    /// Presents an `NSSavePanel` to save `content` as a `.txt` file.
    ///
    /// - Parameters:
    ///   - content: The ASCII art string to write.
    ///   - suggestedFilename: The base filename to suggest (e.g. the source image's name
    ///     without extension). The `.txt` extension is appended automatically.
    ///   - directoryURL: Optional starting directory for the save panel.
    /// - Returns: `true` if the file was saved successfully, `false` if the user cancelled.
    @MainActor
    @discardableResult
    public static func save(
        content: String,
        suggestedFilename: String,
        directoryURL: URL? = nil
    ) -> Bool {
        let panel = NSSavePanel()
        panel.title = "Save ASCII Art"
        panel.nameFieldStringValue =
            (suggestedFilename as NSString)
            .appendingPathExtension("txt") ?? "\(suggestedFilename).txt"
        panel.allowedContentTypes = [.plainText]
        panel.directoryURL = directoryURL

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            // Surface the error in the panel.
            let alert = NSAlert()
            alert.messageText = "Could not save ASCII art"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return false
        }
    }

    // MARK: - Open

    /// Presents an `NSOpenPanel` to load a `.txt` ASCII art file.
    ///
    /// - Parameter directoryURL: Optional starting directory.
    /// - Returns: A tuple of (content, filenameWithoutExtension) if a file was selected
    ///            and read successfully, or `nil` if the user cancelled.
    @MainActor
    public static func open(directoryURL: URL? = nil) -> (content: String, filename: String)? {
        let panel = NSOpenPanel()
        panel.title = "Open ASCII Art"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.directoryURL = directoryURL

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let filename = url.deletingPathExtension().lastPathComponent
            return (content, filename)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not open file"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return nil
        }
    }
}
