import Foundation

/// Validates a file's size and encoding before any content is loaded into `NSTextStorage`.
///
/// SR-3: refusal happens *before* any memory allocation for the file content so an
/// oversized or binary file never exhausts RAM in the text storage.
public enum EncodingGuard {

    /// Maximum file size (in bytes) this editor will attempt to open.
    ///
    /// Callers should pass `SettingsStore.editorMaxFileSizeBytes`; this constant
    /// is the fallback for contexts where settings are unavailable.
    public static let defaultMaxBytes: Int = 10 * 1024 * 1024  // 10 MB

    // MARK: - Errors

    public enum Failure: Error, Sendable {
        /// The file exceeds the permitted size limit.
        case fileTooLarge(url: URL, size: Int, limit: Int)
        /// The file contains binary data or cannot be decoded as text.
        case binaryOrUnreadable(url: URL)
    }

    // MARK: - Validation

    /// Checks file size and probes a leading chunk for encoding; throws on failure.
    ///
    /// Returns the detected `String.Encoding` on success. Never loads the full file
    /// into memory — only the first 8 KB is read for the encoding probe.
    ///
    /// - Parameters:
    ///   - url:      File to validate. Must be a file URL.
    ///   - maxBytes: Override the default size cap (primarily for testing).
    public static func validate(
        _ url: URL,
        maxBytes: Int = defaultMaxBytes
    ) throws -> String.Encoding {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size  = (attrs[.size] as? Int) ?? 0
        guard size <= maxBytes else {
            throw Failure.fileTooLarge(url: url, size: size, limit: maxBytes)
        }

        // Read a small leading chunk; avoids loading large files into memory.
        let probeSize = min(size, 8 * 1024)
        let handle    = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let probeData = handle.readData(ofLength: probeSize)

        // Reject clearly binary content: >15 % null bytes in the probe indicates binary.
        if probeSize > 0 {
            let nullCount = probeData.filter { $0 == 0x00 }.count
            if Double(nullCount) / Double(probeSize) > 0.15 {
                throw Failure.binaryOrUnreadable(url: url)
            }
        }

        // Try common encodings in preference order.
        let candidates: [String.Encoding] = [.utf8, .utf16, .isoLatin1, .windowsCP1252]
        for enc in candidates {
            if String(data: probeData, encoding: enc) != nil {
                return enc
            }
        }
        throw Failure.binaryOrUnreadable(url: url)
    }
}
