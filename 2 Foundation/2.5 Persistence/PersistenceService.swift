import Foundation

/// Contract for all durable storage in Sputnik.
///
/// No module should touch `UserDefaults`, `FileManager`, or the file system directly.
/// Instead, every module calls this protocol. The concrete implementation,
/// `FilePersistenceService`, is registered at app startup and injected via the app's
/// environment or a shared accessor.
@MainActor
public protocol PersistenceService: AnyObject {

    // MARK: Layout

    /// Reads `layout.json` and returns the last-saved `LayoutState`, or `.default` if
    /// the file is absent or corrupt.
    func restore() async -> LayoutState

    /// Writes the current `LayoutState` to `layout.json` synchronously on a utility task.
    func flushLayout(_ state: LayoutState)

    // MARK: Crash recovery

    /// Writes `content` to `recovery/<filename>.recovery` so that an unclean shutdown
    /// can be detected and surfaced to the user on next launch.
    /// - Parameters:
    ///   - url:     The `URL` of the file being edited (used to derive the recovery filename).
    ///   - content: The current text content to persist.
    func writeRecovery(for url: URL, content: String)

    /// Deletes the recovery file for `url` after the file has been cleanly saved.
    func clearRecovery(for url: URL)

    /// Returns the file names (without the `.recovery` extension) of any pending recovery
    /// files found in the recovery directory.
    func pendingRecoveryNames() -> [String]

    // MARK: Settings (UserDefaults)

    /// Persists an `Encodable` value under `key` in `UserDefaults`.
    func saveSetting<T: Encodable>(_ value: T, forKey key: String)

    /// Loads a `Decodable` value for `key` from `UserDefaults`, returning `nil` if absent
    /// or if decoding fails.
    func loadSetting<T: Decodable>(forKey key: String) -> T?
}
