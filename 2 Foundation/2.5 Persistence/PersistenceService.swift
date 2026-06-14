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

    /// Writes the current `LayoutState` to `layout.json` on a utility actor (async).
    func flushLayout(_ state: LayoutState)

    /// Encodes and writes layout state synchronously — for use in `applicationWillTerminate` only,
    /// where fire-and-forget Tasks are never scheduled before the process exits.
    func flushLayoutSync(_ state: LayoutState)

    // MARK: Multi-window persistence

    /// Reads `windows.json` and returns the last-saved window descriptors, or an
    /// empty array if the file is absent or corrupt.
    func restoreWindows() async -> [WindowDescriptor]

    /// Writes the given window descriptors to `windows.json` on a utility actor (async).
    func saveWindows(_ descriptors: [WindowDescriptor])

    /// Encodes and writes window descriptors synchronously — for use in `applicationWillTerminate`
    /// only, where fire-and-forget Tasks are never scheduled before the process exits.
    func saveWindowsSync(_ descriptors: [WindowDescriptor])

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

    // MARK: Scratchpad (F-6)

    /// Persists the scratchpad text to UserDefaults.
    func saveScratchpad(text: String)

    /// Returns the previously saved scratchpad text, or an empty string.
    func loadScratchpadText() -> String

    /// Persists the docked scratchpad width to UserDefaults.
    func saveScratchpadDockedWidth(_ width: CGFloat)

    /// Returns the previously saved docked scratchpad width, or 280 if not yet saved.
    func loadScratchpadDockedWidth() -> CGFloat
}
