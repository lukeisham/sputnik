import Foundation

/// Pure functions for discovering and substituting `{{key}}` placeholders in template text.
///
/// No instances — all methods are static so callers have no side-effect surface to worry about.
public enum TemplatePlaceholderExpander {

    /// Matches `{{key}}` tokens where `key` is one or more non-whitespace, non-brace characters.
    /// Compiled once as a static constant to avoid repeated compilation (cf. ISS-122).
    private static let pattern: NSRegularExpression = {
        // Force-try is safe: the pattern is a compile-time constant.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#)
    }()

    /// Returns the unique placeholder keys found in `content`, in order of first appearance.
    ///
    /// Example: `"Hello {{name}}, today is {{date}}."` → `["name", "date"]`.
    public static func placeholders(in content: String) -> [String] {
        let range = NSRange(content.startIndex..., in: content)
        let matches = pattern.matches(in: content, range: range)
        var seen: Set<String> = []
        var ordered: [String] = []
        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: content) else { continue }
            let key = String(content[keyRange])
            if seen.insert(key).inserted {
                ordered.append(key)
            }
        }
        return ordered
    }

    /// Replaces every `{{key}}` occurrence in `template` with the corresponding value
    /// from `values`. Keys absent from `values` are replaced with an empty string.
    ///
    /// - Parameters:
    ///   - template: The raw template string.
    ///   - values:   A dictionary mapping placeholder keys to their substitution values.
    /// - Returns: The expanded string.
    public static func expand(template: String, values: [String: String]) -> String {
        var result = template
        let allKeys = placeholders(in: template)
        for key in allKeys {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: values[key] ?? "")
        }
        return result
    }

    /// Builds a seed dictionary with auto-filled values for well-known placeholder keys.
    ///
    /// Currently seeds:
    /// - `"date"` → today's date formatted as `YYYY-MM-DD`.
    public static func defaultValues(for keys: [String]) -> [String: String] {
        var values: [String: String] = [:]
        let today = isoDateFormatter.string(from: Date())
        for key in keys where key == "date" {
            values[key] = today
        }
        return values
    }

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
