import Foundation

/// Concrete `PersistenceService` backed by `UserDefaults` and
/// `~/Library/Application Support/Sputnik/`.
///
/// This type is instantiated once in `SputnikApp` and injected into the environment.
/// All methods run on `@MainActor`; file I/O is dispatched on a `.utility` `Task` so the
/// main thread is never blocked by disk writes.
@MainActor
public final class FilePersistenceService: PersistenceService {

    // MARK: - Constants

    private enum Keys {
        static let layoutFilename = "layout.json"
        static let recoveryDirectory = "recovery"
        static let recoveryExtension = "recovery"
    }

    // MARK: - Support directory

    /// Resolved once at init; all file I/O uses this path.
    private let supportDirectory: URL

    public init() {
        let base =
            FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory

        supportDirectory = base.appendingPathComponent("Sputnik", isDirectory: true)
        createDirectoriesIfNeeded()
    }

    private func createDirectoriesIfNeeded() {
        let recovery = supportDirectory.appendingPathComponent(
            Keys.recoveryDirectory, isDirectory: true
        )
        for url in [supportDirectory, recovery] {
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.createDirectory(
                    at: url, withIntermediateDirectories: true
                )
            } catch {
                // Non-fatal: subsequent writes will surface errors individually.
            }
        }
    }

    // MARK: - Layout

    public func restore() async -> LayoutState {
        let layoutURL = supportDirectory.appendingPathComponent(Keys.layoutFilename)
        guard FileManager.default.fileExists(atPath: layoutURL.path) else {
            return .default
        }
        do {
            let data = try Data(contentsOf: layoutURL)
            return try JSONDecoder().decode(LayoutState.self, from: data)
        } catch {
            // Corrupt file — return default; the next `flushLayout` overwrites it.
            return .default
        }
    }

    public func flushLayout(_ state: LayoutState) {
        let layoutURL = supportDirectory.appendingPathComponent(Keys.layoutFilename)
        Task(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(state)
                try data.write(to: layoutURL, options: .atomic)
            } catch {
                // Layout flush failure is non-fatal; worst case the layout resets on next launch.
            }
        }
    }

    // MARK: - Crash recovery

    private func recoveryURL(for url: URL) -> URL {
        let name = url.deletingPathExtension().lastPathComponent
        return
            supportDirectory
            .appendingPathComponent(Keys.recoveryDirectory, isDirectory: true)
            .appendingPathComponent("\(name).\(Keys.recoveryExtension)")
    }

    public func writeRecovery(for url: URL, content: String) {
        let target = recoveryURL(for: url)
        Task(priority: .utility) {
            do {
                try content.write(to: target, atomically: true, encoding: .utf8)
            } catch {
                // Recovery write failure is non-fatal; the user may lose changes only on crash.
            }
        }
    }

    public func clearRecovery(for url: URL) {
        let target = recoveryURL(for: url)
        Task(priority: .utility) {
            guard FileManager.default.fileExists(atPath: target.path) else { return }
            do {
                try FileManager.default.removeItem(at: target)
            } catch {
                // Non-fatal; stale recovery files are overwritten on next edit.
            }
        }
    }

    public func pendingRecoveryNames() -> [String] {
        let dir = supportDirectory.appendingPathComponent(
            Keys.recoveryDirectory, isDirectory: true
        )
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            )
        else {
            return []
        }
        return
            contents
            .filter { $0.pathExtension == Keys.recoveryExtension }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    // MARK: - Settings

    public func saveSetting<T: Encodable>(_ value: T, forKey key: String) {
        Task(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(value)
                UserDefaults.standard.set(data, forKey: key)
            } catch {
                // Encoding failure for settings is non-fatal.
            }
        }
    }

    public func loadSetting<T: Decodable>(forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Scratchpad (F-6)

    private enum ScratchpadKeys {
        static let text = "scratchpadText"
        static let frame = "scratchpadFrame"
    }

    public func saveScratchpad(text: String) {
        UserDefaults.standard.set(text, forKey: ScratchpadKeys.text)
    }

    public func loadScratchpadText() -> String {
        UserDefaults.standard.string(forKey: ScratchpadKeys.text) ?? ""
    }

    public func saveScratchpad(frame: CGRect) {
        // CGRect is not Codable by default, so encode its components as a dictionary.
        let dict: [String: Double] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height,
        ]
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: ScratchpadKeys.frame)
        }
    }

    public func loadScratchpadFrame() -> CGRect {
        guard let data = UserDefaults.standard.data(forKey: ScratchpadKeys.frame),
            let dict = try? JSONDecoder().decode([String: Double].self, from: data),
            let x = dict["x"],
            let y = dict["y"],
            let w = dict["width"],
            let h = dict["height"]
        else {
            return CGRect(x: 0, y: 0, width: 320, height: 240)
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
