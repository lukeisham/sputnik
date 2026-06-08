import Foundation

/// A cross-`Task`-safe description of the editor font.
///
/// Wraps a PostScript font name and point size rather than an `NSFont` reference so it
/// can be passed freely across `Task` boundaries without triggering sendability errors.
public struct EditorFont: Codable, Sendable, Equatable {
    /// The PostScript name of the font (e.g. `"SFMono-Regular"`).
    public var postScriptName: String
    /// The point size of the font.
    public var pointSize: CGFloat

    public init(postScriptName: String = "SFMono-Regular", pointSize: CGFloat = 13) {
        self.postScriptName = postScriptName
        self.pointSize = pointSize
    }
}
