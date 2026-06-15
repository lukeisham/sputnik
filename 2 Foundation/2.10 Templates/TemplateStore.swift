import Foundation

/// Manages the on-disk template library and provides CRUD operations.
///
/// All file I/O is actor-isolated so it never touches the main thread (SR-4).
/// The directory to scan is configurable via `setDirectory(_:)` so the user can
/// point to a custom folder from Settings (2.3). On first access the default
/// `~/Library/Application Support/Sputnik/Templates/` is used.
public actor TemplateStore {

    // MARK: - Shared singleton

    public static let shared = TemplateStore()

    // MARK: - State

    /// The folder currently being scanned. Updated by `setDirectory(_:)`.
    private var directoryURL: URL

    // MARK: - Init

    /// Use `TemplateStore.shared` in production.
    /// `internal` (not `private`) so `@testable import FoundationModule` can create isolated instances.
    init() {
        directoryURL = TemplateStore.defaultDirectoryURL()
    }

    // MARK: - Directory management

    /// Returns the default templates folder under Application Support.
    public static func defaultDirectoryURL() -> URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Sputnik/Templates")
    }

    /// Updates the directory and creates it on disk if it does not exist.
    /// Called by `AppState.applyTemplateDirectory(_:)` when the user changes the
    /// folder in Settings.
    public func setDirectory(_ url: URL) async {
        directoryURL = url
        ensureDirectory(url)
    }

    // MARK: - Bootstrap

    /// Creates the directory and seeds starter templates if it is empty.
    /// Called once at app launch via `AppState.applyTemplateDirectory(nil)`.
    public func bootstrap() async {
        ensureDirectory(directoryURL)
        seedIfEmpty()
    }

    // MARK: - Queries

    /// All template files in the current directory, sorted by name.
    public func templates() -> [TemplateRecord] {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles])
        else { return [] }

        let allowed: Set<String> = ["md", "html", "htm", "ascii", "asc", "txt"]
        return entries
            .filter { allowed.contains($0.pathExtension.lowercased()) }
            .map { TemplateRecord(url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Reads and returns the raw text content of a template file.
    ///
    /// Content is not cached — it is read fresh on every call (SR-3).
    public func rawContent(of record: TemplateRecord) throws -> String {
        do {
            return try String(contentsOf: record.id, encoding: .utf8)
        } catch {
            throw SputnikAlert.fileReadFailed(record.id, underlyingError: error.localizedDescription)
        }
    }

    // MARK: - Mutations

    /// Writes a new template file to the current directory.
    ///
    /// - Throws: `SputnikAlert.fileWriteFailed` on I/O error, or
    ///   `.custom` when a file with the same name already exists.
    public func save(name: String, content: String, fileExtension: String) throws {
        let filename = "\(name).\(fileExtension)"
        let dest = directoryURL.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            throw SputnikAlert.custom(
                title: "Template Already Exists",
                message: "A template named \"\(name)\" already exists. Choose a different name.")
        }
        do {
            try content.write(to: dest, atomically: true, encoding: .utf8)
        } catch {
            throw SputnikAlert.fileWriteFailed(dest, underlyingError: error.localizedDescription)
        }
    }

    /// Moves a template file to the Trash.
    ///
    /// - Throws: `SputnikAlert.fileWriteFailed` when the trash operation fails.
    public func delete(record: TemplateRecord) throws {
        do {
            try FileManager.default.trashItem(at: record.id, resultingItemURL: nil)
        } catch {
            throw SputnikAlert.fileWriteFailed(
                record.id, underlyingError: error.localizedDescription)
        }
    }

    // MARK: - Private helpers

    private func ensureDirectory(_ url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true, attributes: nil)
    }

    private func seedIfEmpty() {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]),
            entries.isEmpty
        else { return }

        let mdContent = """
            # {{title}}

            **Date:** {{date}}
            **Author:** {{author}}

            ---

            Write your content here.
            """

        let htmlContent = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <title>{{title}}</title>
            </head>
            <body>
                <h1>{{title}}</h1>
                <p>Created on {{date}} by {{author}}.</p>
            </body>
            </html>
            """

        let seeds: [(String, String)] = [
            ("Starter", "md"),
            ("Starter", "html"),
        ]
        for (name, ext) in seeds {
            let content = ext == "md" ? mdContent : htmlContent
            try? save(name: name, content: content, fileExtension: ext)
        }
    }
}
