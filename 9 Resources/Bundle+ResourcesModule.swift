import Foundation

/// Public accessor for the ResourcesModule resource bundle.
///
/// Other modules that depend on ResourcesModule (transitively via the main app)
/// use `Bundle.resourcesModule` to locate bundled resource files instead of
/// `Bundle.main`, which does not contain SPM library resources.
extension Bundle {
    /// The resource bundle for `ResourcesModule`, containing JSON indexes,
    /// Markdown topic bodies, ASCII art files, and completion corpora.
    public static let resourcesModule: Bundle = Bundle.module
}
