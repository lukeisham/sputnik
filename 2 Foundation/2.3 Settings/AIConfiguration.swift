import Foundation

/// AI provider configuration (Sendable, Codable).
///
/// API key is NOT stored here — it lives in the Keychain. This struct holds the
/// model name and optional base URL for the AI provider endpoint.
public struct AIConfiguration: Codable, Sendable, Equatable {
    /// The AI model identifier (e.g. "claude-sonnet-4-20250514").
    public var modelName: String

    /// An optional base URL override for self-hosted or proxy endpoints.
    /// When `nil`, the default provider URL is used.
    public var baseURL: URL?

    public init(modelName: String = "", baseURL: URL? = nil) {
        self.modelName = modelName
        self.baseURL = baseURL
    }
}
