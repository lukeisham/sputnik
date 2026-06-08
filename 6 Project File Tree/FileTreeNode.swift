import Foundation

/// A single file or folder node in the project tree.
///
/// Value type so instances cross actor boundaries safely when background scans
/// build subtrees and merge them back onto `@MainActor` (SW-1).
public struct FileTreeNode: Identifiable, Sendable, Hashable, Equatable {

    /// Stable identity — the absolute file URL on disk.
    public let id: URL

    /// Display name (`lastPathComponent`).
    public let name: String

    public let isDirectory: Bool

    /// `nil` = not yet expanded; `[]` = expanded but empty folder.
    public var children: [FileTreeNode]?

    public let fileType: FileType

    public let modificationDate: Date?

    /// `false` when permission was denied reading this item (shows a lock icon).
    public let isReadable: Bool

    // MARK: - SF Symbol icon

    /// SF Symbol name that best represents this node, based on type and read permission.
    public var icon: String {
        guard isReadable else { return "lock.doc" }
        if isDirectory {
            return (children?.isEmpty == false) ? "folder.fill" : "folder"
        }
        switch fileType {
        case .markdown: return "doc.richtext"
        case .html:     return "chevron.left.slash.chevron.right"
        case .pdf:      return "doc.text.below.ecg"
        case .ascii:    return "doc.text.image"
        case .text:     return "doc.plaintext"
        case .binary:   return "doc.zipper"
        case .unknown:  return "doc"
        }
    }

    // MARK: - Init

    public init(
        id: URL,
        name: String,
        isDirectory: Bool,
        children: [FileTreeNode]?,
        fileType: FileType,
        modificationDate: Date?,
        isReadable: Bool
    ) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.children = children
        self.fileType = fileType
        self.modificationDate = modificationDate
        self.isReadable = isReadable
    }
}
