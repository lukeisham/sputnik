import Foundation

/// Supported AI providers for the Supporting AI role.
///
/// Each case provides a `defaultBaseURL` used when no explicit `baseURL` override
/// is set in `SupportingAIConfiguration`.
public enum SupportingAIProvider: String, Codable, Sendable, CaseIterable {
    case deepSeek = "deepseek"
    case gemini = "gemini"
    case local = "local"

    /// The default API base URL for this provider.
    public var defaultBaseURL: URL {
        switch self {
        case .deepSeek:
            return URL(string: "https://api.deepseek.com")!
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com")!
        case .local:
            return URL(string: "http://localhost:11434")!
        }
    }
}

/// Supporting AI provider configuration (Sendable, Codable).
///
/// The Supporting AI is the app's built-in AI service used exclusively for resource
/// features: help lookups, completions, and More Context. It is **not** the Main AI
/// (the user-loaded AI in the terminal).
///
/// API key is NOT stored here — it lives in the Keychain under the service label
/// `"com.sputnik.supportingAIKey"`. This struct holds the provider selection, model
/// name, and optional base URL override.
public struct SupportingAIConfiguration: Codable, Sendable, Equatable {
    /// The selected AI provider.
    public var provider: SupportingAIProvider

    /// The AI model identifier (e.g. "deepseek-chat", "gemini-1.5-pro").
    public var modelName: String

    /// An optional base URL override for self-hosted or proxy endpoints.
    /// When `nil`, the provider's `defaultBaseURL` is used.
    public var baseURL: URL?

    /// The resolved base URL: the override if set, otherwise the provider default.
    public var resolvedBaseURL: URL {
        baseURL ?? provider.defaultBaseURL
    }

    public init(
        provider: SupportingAIProvider = .deepSeek,
        modelName: String = "",
        baseURL: URL? = nil
    ) {
        self.provider = provider
        self.modelName = modelName
        self.baseURL = baseURL
    }
}
