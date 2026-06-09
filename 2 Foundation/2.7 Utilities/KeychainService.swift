import Foundation
import Security

/// Thin wrapper around the Security.framework Keychain C API.
///
/// All methods are synchronous (the `SecItem*` C API has no async variant — documented
/// per MR-3). Call from any thread; Keychain operations are inherently thread-safe.
///
/// Service label: `"com.sputnik.aiAPIKey"`
@MainActor
public enum KeychainService {

    /// The Keychain service name used for the AI API key.
    private static let service = "com.sputnik.aiAPIKey"

    // MARK: - Errors

    /// Errors that can occur during Keychain operations.
    public enum KeychainError: Error, CustomStringConvertible {
        /// `SecItemAdd` failed with the given OSStatus code.
        case saveFailed(OSStatus)
        /// `SecItemCopyMatching` failed with the given OSStatus code.
        case loadFailed(OSStatus)
        /// `SecItemDelete` failed with the given OSStatus code.
        case deleteFailed(OSStatus)
        /// The data returned by the Keychain could not be interpreted as a UTF-8 string.
        case unexpectedData

        public var description: String {
            switch self {
            case .saveFailed(let s): return "Keychain save failed: \(s)"
            case .loadFailed(let s): return "Keychain load failed: \(s)"
            case .deleteFailed(let s): return "Keychain delete failed: \(s)"
            case .unexpectedData: return "Keychain returned unexpected data format"
            }
        }
    }

    // MARK: - Public API

    /// Stores an API key string in the Keychain.
    ///
    /// If an existing item with the same service label is present, it is deleted
    /// first (effectively an upsert). The item is marked accessible after first
    /// device unlock so that background tasks can read it.
    ///
    /// - Parameter key: The API key string to store.
    /// - Throws: `KeychainError.saveFailed` if the underlying `SecItemAdd` call fails.
    public static func save(key: String) throws {
        // Delete existing item first to avoid duplicates.
        try? delete()

        guard let data = key.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Loads the API key string from the Keychain.
    ///
    /// - Returns: The stored API key string, or `nil` if no item exists for the service label.
    /// - Throws: `KeychainError.loadFailed` or `KeychainError.unexpectedData` on error.
    public static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes the API key item from the Keychain.
    ///
    /// This is a no-op (does not throw) if no item exists for the service label.
    /// - Throws: `KeychainError.deleteFailed` if the underlying `SecItemDelete` call fails
    ///           for a reason other than `errSecItemNotFound`.
    public static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
