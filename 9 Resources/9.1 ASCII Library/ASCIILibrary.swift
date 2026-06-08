import Foundation

/// Thread-safe, lazy-loading access point for the bundled ASCII art collection.
///
/// The index metadata is loaded once on first access and held in memory.
/// Art file content is read from disk per `art(id:)` call and never cached
/// beyond the caller's scope (SR-3).
///
/// Consumers bridge the actor boundary with `await`:
/// ```swift
/// let results = await ASCIILibrary.shared.search(query: "cat")
/// if let content = await ASCIILibrary.shared.art(id: results.first?.id) { ... }
/// ```
public actor ASCIILibrary {

    // MARK: - Shared instance

    public static let shared = ASCIILibrary()

    // MARK: - State

    private var records: [ASCIIArtRecord] = []
    private var didLoad = false

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    public func search(query: String) async -> [ASCIIArtRecord] {
        await ensureLoaded()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return records }
        return records.filter { r in
            r.title.lowercased().contains(q)
                || r.tags.contains { $0.lowercased().contains(q) }
        }
    }

    public func search(category: String) async -> [ASCIIArtRecord] {
        await ensureLoaded()
        return records.filter { $0.category == category }
    }

    public func art(id: String) async -> String? {
        await ensureLoaded()
        guard let record = records.first(where: { $0.id == id }) else { return nil }
        return loadArtFile(named: record.filename)
    }

    public func categories() async -> [String] {
        await ensureLoaded()
        var seen: [String] = []
        for r in records where !seen.contains(r.category) {
            seen.append(r.category)
        }
        return seen
    }

    // MARK: - Private helpers

    private func ensureLoaded() async {
        guard !didLoad else { return }
        didLoad = true
        loadIndex()
    }

    private func loadIndex() {
        guard
            let url = Bundle.main.url(forResource: "index", withExtension: "json",
                                      subdirectory: "ASCIILibrary"),
            let data = try? Data(contentsOf: url),
            let index = try? JSONDecoder().decode(ASCIILibraryIndex.self, from: data)
        else { return }
        records = index.records
    }

    private func loadArtFile(named filename: String) -> String? {
        // filename is e.g. "Arrows/simple_right.txt"
        let components = filename.split(separator: "/", maxSplits: 1)
        guard components.count == 2 else { return nil }
        let subdir = "ASCIILibrary/" + components[0]
        let file = String(components[1])
        let nameWithoutExt = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: nameWithoutExt, withExtension: ext,
                                        subdirectory: subdir)
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
