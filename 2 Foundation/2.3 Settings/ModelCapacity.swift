import Foundation

/// Known model context-window sizes (in tokens).
///
/// Shared by F-5 (context % display) and F-8 (terminal model detection).
/// Add new models here as they become available.
public enum ModelCapacity {
    /// Returns the context-window token count for a known model name, or `nil` if
    /// the model is unrecognised.
    ///
    /// Matching is case-insensitive and substring-based so that versioned identifiers
    /// (e.g. "claude-sonnet-4-20250514") are recognised.
    public static func contextWindow(for modelName: String) -> Int? {
        let lower = modelName.lowercased()
        if lower.contains("claude-sonnet-4") { return 200_000 }
        if lower.contains("claude-opus-4") { return 200_000 }
        if lower.contains("claude-3-5-sonnet") { return 200_000 }
        if lower.contains("claude-3-opus") { return 200_000 }
        if lower.contains("claude-3-haiku") { return 200_000 }
        if lower.contains("gpt-4") { return 128_000 }
        if lower.contains("gpt-3.5") { return 16_000 }
        if lower.contains("llama3") { return 8_192 }
        if lower.contains("llama2") { return 4_096 }
        if lower.contains("mistral") { return 32_000 }
        if lower.contains("codestral") { return 32_000 }
        return nil
    }
}
