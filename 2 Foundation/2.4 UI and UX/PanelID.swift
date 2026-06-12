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
    /// Returns `nil` for panels that should not show a badge (help panels only).
    public var displayBadge: String? {
        switch self {
        case .textEditor: return "EDITOR"
        case .markdownPreview: return "MD"
        case .htmlPreview: return "HTML"
        case .pdfViewer: return "PDF"
        case .asciiStudio: return "ASCII"
        case .fileTree: return "FILES"
        case .asciiArtHelp, .markdownHelp, .htmlHelp, .grammarHelp: return nil
        }
    }

    /// Human-readable display name used in menus, accessibility labels, and tooltips.
    /// This is the single source of truth for panel identity across the app.
    public var displayName: String {
        switch self {
        case .fileTree: return "File Tree"
        case .textEditor: return "Editor"
        case .markdownPreview: return "Markdown Preview"
        case .htmlPreview: return "HTML Preview"
        case .pdfViewer: return "Viewer"
        case .asciiStudio: return "ASCII Studio"
        case .asciiArtHelp: return "ASCII Art Help"
        case .markdownHelp: return "Markdown Help"
        case .htmlHelp: return "HTML Help"
        case .grammarHelp: return "Grammar Help"
        }
    }
}
