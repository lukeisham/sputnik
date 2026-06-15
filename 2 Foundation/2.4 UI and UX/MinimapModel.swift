import Foundation

// MARK: - LineKind

/// Classifies a source line for minimap rendering.
/// All cases are `Sendable` so the model can be built off the main actor.
public enum LineKind: Sendable {
    /// A blank or whitespace-only line.
    case blank
    /// A plain-text line.
    case plain
    /// A Markdown heading line (starts with `#`).
    case heading
    /// A fenced-code-block line or indented code line.
    case code
    /// A blockquote line (starts with `>`).
    case quote
    /// A list-item line (starts with `-`, `*`, `+`, or a number followed by `.`).
    case list
}

// MARK: - MinimapLine

/// A single line in the minimap model.
public struct MinimapLine: Sendable {
    /// Fractional bar length (0.0 … 1.0), relative to the longest line in the document.
    public let lengthFraction: Double
    /// The visual kind of the line.
    public let kind: LineKind

    public init(lengthFraction: Double, kind: LineKind) {
        self.lengthFraction = max(0, min(1.0, lengthFraction))
        self.kind = kind
    }
}

// MARK: - MinimapModel

/// The minimap model — a lightweight array of per-line descriptors.
public struct MinimapModel: Sendable {
    /// Ordered lines, one per source line.
    public let lines: [MinimapLine]

    public init(lines: [MinimapLine]) {
        self.lines = lines
    }

    /// An empty model (no content to display).
    public static let empty = MinimapModel(lines: [])
}

// MARK: - MinimapModelBuilder

/// Builds a `MinimapModel` from raw text by splitting into lines, classifying each,
/// and normalising bar lengths.
///
/// Pure value type — no AppKit/UIKit dependencies. Safe to run off the main actor.
public struct MinimapModelBuilder: Sendable {

    public init() {}

    /// Builds a minimap model from the given text.
    ///
    /// - Parameter text: The full document text.
    /// - Returns: A `MinimapModel` with one `MinimapLine` per source line.
    public func build(from text: String) -> MinimapModel {
        let rawLines = text.components(separatedBy: "\n")
        // Empty string yields [""] — treat as truly empty.
        guard !rawLines.isEmpty, !(rawLines.count == 1 && rawLines[0].isEmpty) else {
            return .empty
        }

        // Compute raw character lengths (for bar-length normalisation).
        let charLengths = rawLines.map { Double($0.count) }
        let maxLength = charLengths.max() ?? 1

        let lines: [MinimapLine] = rawLines.enumerated().map { index, rawLine in
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let kind = Self.classify(line: trimmed)
            let lengthFraction =
                maxLength > 0
                ? min(1.0, charLengths[index] / maxLength)
                : 0
            return MinimapLine(lengthFraction: lengthFraction, kind: kind)
        }

        return MinimapModel(lines: lines)
    }

    // MARK: - Classification

    /// Classifies a trimmed source line into a `LineKind`.
    public static func classify(line trimmed: String) -> LineKind {
        if trimmed.isEmpty {
            return .blank
        }

        // Headings: start with 1-6 `#` characters followed by a space.
        if let first = trimmed.first, first == "#" {
            let prefix = trimmed.prefix(while: { $0 == "#" })
            if prefix.count <= 6,
                trimmed.dropFirst(prefix.count).hasPrefix(" ")
            {
                return .heading
            }
        }

        // Blockquote: starts with `>`.
        if trimmed.hasPrefix(">") {
            return .quote
        }

        // Unordered list: starts with `- `, `* `, or `+ `.
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return .list
        }

        // Ordered list: starts with a number followed by `. `.
        if let firstChar = trimmed.first, firstChar.isNumber {
            if let dotIndex = trimmed.firstIndex(of: ".") {
                let prefix = trimmed[trimmed.startIndex..<dotIndex]
                if prefix.allSatisfy({ $0.isNumber }),
                    trimmed.dropFirst(prefix.count + 1).hasPrefix(" ")
                {
                    return .list
                }
            }
        }

        // Fenced code block: starts with ``` or ~~~.
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            return .code
        }

        // Indented code: 4+ spaces at start (but not inside a list or blockquote).
        if trimmed.hasPrefix("    ") {
            return .code
        }

        return .plain
    }
}
