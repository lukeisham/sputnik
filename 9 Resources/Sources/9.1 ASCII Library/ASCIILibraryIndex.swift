import Foundation

/// Root container decoded from `9 Resources/9.1 ASCIILibrary/index.json`.
public struct ASCIILibraryIndex: Codable, Sendable {
    public let records: [ASCIIArtRecord]

    public init(records: [ASCIIArtRecord]) {
        self.records = records
    }
}
