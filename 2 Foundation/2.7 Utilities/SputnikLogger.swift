import os

/// Shared structured-logging channels for all Sputnik modules.
///
/// Use the appropriate channel for the module emitting the log. All channels share
/// the `com.sputnik` subsystem so they appear together in Console.app when filtered
/// by subsystem, while individual categories allow per-module filtering.
public enum SputnikLogger {
    public static let foundation = Logger(subsystem: "com.sputnik", category: "foundation")
    public static let editor     = Logger(subsystem: "com.sputnik", category: "editor")
    public static let fileTree   = Logger(subsystem: "com.sputnik", category: "fileTree")
    public static let terminal   = Logger(subsystem: "com.sputnik", category: "terminal")
    public static let preview    = Logger(subsystem: "com.sputnik", category: "preview")
}
