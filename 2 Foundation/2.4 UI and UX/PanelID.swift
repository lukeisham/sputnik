import Foundation

/// Identifies each relocatable panel.
///
/// The Terminal panel is deliberately excluded — it is pinned to the bottom strip and
/// cannot be moved into the named slot system.
public enum PanelID: String, Codable, Sendable, CaseIterable, Hashable {
    case fileTree
    case textEditor
    case markdownPreview
    case htmlPreview
    case pdfViewer

    // MARK: ASCII Studio (module 10)
    case asciiStudio

    // MARK: Help panels (module 9 Resources)
    case asciiArtHelp
    case markdownHelp
    case htmlHelp
    case grammarHelp

    /// Short label for badge display in column tabs.
    /// Returns `nil` for panels that should not show a badge (file tree, help panels).
    public var displayBadge: String? {
        switch self {
        case .textEditor: return "TXT"
        case .markdownPreview: return "MD"
        case .htmlPreview: return "HTML"
        case .pdfViewer: return "PDF"
        case .asciiStudio: return "ASCII"
        case .fileTree: return nil
        case .asciiArtHelp, .markdownHelp, .htmlHelp, .grammarHelp: return nil
        }
    }
}
