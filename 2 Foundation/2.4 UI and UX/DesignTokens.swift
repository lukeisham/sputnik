import SwiftUI

/// Constant spacing values shared across all Sputnik panels.
public enum SputnikSpacing {
    /// 4 pt — tight spacing between related items inside a single component.
    public static let xs: CGFloat = 4
    /// 8 pt — standard intra-component padding.
    public static let sm: CGFloat = 8
    /// 16 pt — standard inter-component margin.
    public static let md: CGFloat = 16
    /// 24 pt — section-level separation.
    public static let lg: CGFloat = 24
    /// 40 pt — panel-level separation.
    public static let xl: CGFloat = 40
}

/// Constant font sizes shared across all Sputnik panels.
///
/// Actual font faces come from `SettingsStore.editorFont`; these sizes are for
/// non-editor UI chrome (toolbar labels, sidebar annotations, etc.).
public enum SputnikFont {
    /// 11 pt — captions and metadata labels.
    public static let caption: CGFloat = 11
    /// 13 pt — body / default UI text.
    public static let body: CGFloat = 13
    /// 15 pt — section headers inside panels.
    public static let headline: CGFloat = 15
    /// 20 pt — top-level panel titles.
    public static let title: CGFloat = 20
}

/// Layout dimensions shared across Sputnik panels.
public enum SputnikLayout {
    /// Height of panel header bars (toolbar rows).
    public static let headerHeight: CGFloat = 32
}
