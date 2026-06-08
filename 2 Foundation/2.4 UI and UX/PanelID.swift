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

    // MARK: Help panels (module 9 Resources)
    case asciiArtHelp
    case markdownHelp
    case htmlHelp
    case grammarHelp
}
