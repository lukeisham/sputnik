import Foundation
import os

/// Concrete `PersistenceService` backed by `UserDefaults` and
/// `~/Library/Application Support/Sputnik/`.
///
/// This type is instantiated once in `SputnikApp` and injected into the environment.
/// All protocol methods run on `@MainActor`. Async file I/O is dispatched through
/// `PersistenceWriter` (an actor) so the main thread is never blocked and writes are
/// serialised to prevent interleaving hazards. Quit-time writes use synchronous methods
/// (`flushLayoutSync`/`saveWindowsSync`) because `applicationWillTerminate` returns
/// before any fire-and-forget Task is scheduled.
@MainActor
public final class FilePersistenceService: PersistenceService {

    // MARK: - Constants

    private enum Keys {
        static let layoutFilename = "layout.json"
        static let windowsFilename = "windows.json"
        static let recoveryDirectory = "recovery"
        static let recoveryExtension = "recovery"
        static let recoverySourcePrefix = "// source: "
    }

    // MARK: - Support directory

    /// Resolved once at init; all file I/O uses this path.
    private let supportDirectory: URL

    private let writer = PersistenceWriter()
    private let logger = Logger(subsystem: "com.sputnik", category: "Persistence")

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
                logger.error("Failed to create directory \(url.path): \(error.localizedDescription)")
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
            logger.warning("Layout restore failed, using default: \(error.localizedDescription)")
            return .default
        }
    }

    public func flushLayout(_ state: LayoutState) {
        let layoutURL = supportDirectory.appendingPathComponent(Keys.layoutFilename)
        Task {
            do {
                try await writer.write(state, to: layoutURL)
            } catch {
                logger.warning("Layout flush failed: \(error.localizedDescription)")
            }
        }
    }

    /// Encodes and writes layout state synchronously. Call only from
    /// `applicationWillTerminate` where async dispatch is not viable.
    public func flushLayoutSync(_ state: LayoutState) {
        let url = supportDirectory.appendingPathComponent(Keys.layoutFilename)
        guard let data = try? JSONEncoder().encode(state) else {
            logger.warning("Layout sync encode failed")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            logger.warning("Layout sync write failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Multi-window persistence

    public func restoreWindows() async -> [WindowDescriptor] {
        let url = supportDirectory.appendingPathComponent(Keys.windowsFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([WindowDescriptor].self, from: data)
        } catch {
            logger.warning("Windows restore failed, using empty: \(error.localizedDescription)")
            return []
        }
    }

    public func saveWindows(_ descriptors: [WindowDescriptor]) {
        let url = supportDirectory.appendingPathComponent(Keys.windowsFilename)
        Task {
            do {
                try await writer.write(descriptors, to: url)
            } catch {
                logger.warning("Windows save failed: \(error.localizedDescription)")
            }
        }
    }

    /// Encodes and writes window descriptors synchronously. Call only from
    /// `applicationWillTerminate` where async dispatch is not viable.
    public func saveWindowsSync(_ descriptors: [WindowDescriptor]) {
        let url = supportDirectory.appendingPathComponent(Keys.windowsFilename)
        guard let data = try? JSONEncoder().encode(descriptors) else {
            logger.warning("Windows sync encode failed")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            logger.warning("Windows sync write failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Crash recovery

    private func recoveryURL(for url: URL) -> URL {
        let hash = stableHash(of: url.path)
        let display = url.deletingPathExtension().lastPathComponent
        let name = "\(display)-\(hash)"
        return supportDirectory
            .appendingPathComponent(Keys.recoveryDirectory, isDirectory: true)
            .appendingPathComponent("\(name).\(Keys.recoveryExtension)")
    }

    /// djb2 hash over the UTF-8 bytes of `string` — stable across process launches,
    /// unlike `String.hashValue` which is randomised per process.
    private func stableHash(of string: String) -> String {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16, uppercase: false)
    }

    public func writeRecovery(for url: URL, content: String) {
        let target = recoveryURL(for: url)
        let headed = "\(Keys.recoverySourcePrefix)\(url.path)\n\(content)"
        Task {
            do {
                try await writer.writeText(headed, to: target)
            } catch {
                logger.error("Recovery write failed for \(url.path): \(error.localizedDescription)")
            }
        }
    }

    public func clearRecovery(for url: URL) {
        let target = recoveryURL(for: url)
        Task {
            do {
                try await writer.remove(at: target)
            } catch {
                logger.error("Recovery clear failed for \(url.path): \(error.localizedDescription)")
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
        return contents
            .filter { $0.pathExtension == Keys.recoveryExtension }
            .compactMap { fileURL -> String? in
                if let text = try? String(contentsOf: fileURL, encoding: .utf8),
                   let firstLine = text.components(separatedBy: "\n").first,
                   firstLine.hasPrefix(Keys.recoverySourcePrefix) {
                    return String(firstLine.dropFirst(Keys.recoverySourcePrefix.count))
                }
                // Legacy fallback: files without the source header surface by filename.
                return fileURL.deletingPathExtension().lastPathComponent
            }
    }

    // MARK: - Settings

    public func saveSetting<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else {
            logger.warning("Settings encode failed for key \(key)")
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    public func loadSetting<T: Decodable>(forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Scratchpad (F-6)

    private enum ScratchpadKeys {
        static let text = "scratchpadText"
        static let dockedWidth = "scratchpadDockedWidth"
    }

    public func saveScratchpad(text: String) {
        UserDefaults.standard.set(text, forKey: ScratchpadKeys.text)
    }

    public func loadScratchpadText() -> String {
        UserDefaults.standard.string(forKey: ScratchpadKeys.text) ?? ""
    }

    public func saveScratchpadDockedWidth(_ width: CGFloat) {
        UserDefaults.standard.set(Double(width), forKey: ScratchpadKeys.dockedWidth)
    }

    public func loadScratchpadDockedWidth() -> CGFloat {
        let value = UserDefaults.standard.double(forKey: ScratchpadKeys.dockedWidth)
        guard value > 0 else { return 280 }
        return CGFloat(min(600, max(200, value)))
    }
}
