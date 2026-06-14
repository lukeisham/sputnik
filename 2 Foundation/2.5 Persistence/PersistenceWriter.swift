import Foundation

/// Serialises all file-system writes through a single actor, preventing interleaving hazards
/// when `flushLayout` and `clearRecovery` are called concurrently. Running on the cooperative
/// thread pool means encode + write never touch the main thread.
actor PersistenceWriter {
    func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    func writeText(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func remove(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
