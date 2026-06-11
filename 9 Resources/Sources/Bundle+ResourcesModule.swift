import Foundation

/// Public accessor for the ResourcesModule resource bundle.
///
/// During development, uses the source-tree resources directly (no bundling).
/// In production, would use Bundle.module if resources were properly bundled.
extension Bundle {
    /// The resource bundle for `ResourcesModule`, containing JSON indexes,
    /// Markdown topic bodies, ASCII art files, and completion corpora.
    public static let resourcesModule: Bundle = {
        // Try to find the 9 Resources directory in the source tree
        // This is a development/debugging path; production would use Bundle.module
        let fileManager = FileManager.default
        let mainBundle = Bundle.main

        // Check main bundle first
        if let resourcePath = mainBundle.path(forResource: "9.1 ASCII Library", ofType: nil) {
            if let bundleURL = mainBundle.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("9 Resources").path as String? {
                if fileManager.fileExists(atPath: bundleURL) {
                    return Bundle(path: bundleURL) ?? mainBundle
                }
            }
        }

        // Fallback to scanning from main bundle to find Resources directory
        var currentURL = mainBundle.bundleURL
        for _ in 0..<5 {
            let resourceDir = currentURL.deletingLastPathComponent().appendingPathComponent("9 Resources")
            if fileManager.fileExists(atPath: resourceDir.path) {
                return Bundle(url: resourceDir) ?? mainBundle
            }
            currentURL = currentURL.deletingLastPathComponent()
        }

        return mainBundle
    }()
}
