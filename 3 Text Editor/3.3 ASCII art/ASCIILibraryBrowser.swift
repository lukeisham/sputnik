import AppKit
import ResourcesModule

/// Lazily loads bundled ASCII-art clip files from `Resources/ASCIILibrary/<category>/`.
///
/// Inserts the selected clip at the cursor via `NSTextStorage` replacement.
/// SR-3: clips are loaded per-category on first access, never all upfront.
/// Missing categories or files degrade silently (guide failure mode — empty library
/// folders are expected during development and are non-blocking).
@MainActor
public final class ASCIILibraryBrowser {

    // MARK: - Types

    public enum Category: String, CaseIterable, Sendable {
        case frames = "Frames"
        case arrows = "Arrows"
        case dividers = "Dividers"
        case decorative = "Decorative"
        case symbols = "Symbols"
    }

    /// A single clip loaded from the library.
    public struct Clip: Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public let content: String

        public init(name: String, content: String) {
            self.id = UUID()
            self.name = name
            self.content = content
        }
    }

    // MARK: - State

    private var cache: [Category: [Clip]] = [:]

    public init() {}

    // MARK: - Public interface

    /// Returns clips for `category`, loading from the app bundle on first access.
    public func clips(for category: Category) -> [Clip] {
        if let cached = cache[category] { return cached }
        let loaded = loadClips(for: category)
        cache[category] = loaded
        return loaded
    }

    /// Inserts `clip` at the current cursor position in `textView`.
    public func insert(_ clip: Clip, into textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let cursorRange = textView.selectedRange()
        storage.replaceCharacters(in: cursorRange, with: clip.content)
    }

    // MARK: - Private

    private func loadClips(for category: Category) -> [Clip] {
        let categoryDir = Bundle.resourcesModule.bundleURL
            .appendingPathComponent("9.1 ASCII Library")
            .appendingPathComponent(category.rawValue)

        guard FileManager.default.fileExists(atPath: categoryDir.path) else {
            // Library directory absent — degrade gracefully (guide failure mode).
            return []
        }

        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: categoryDir,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension.lowercased() == "txt" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            return []
        }

        return urls.compactMap { url -> Clip? in
            guard let content = try? String(contentsOf: url, encoding: .utf8),
                !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            return Clip(name: name, content: content)
        }
    }
}
