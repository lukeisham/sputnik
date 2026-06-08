import Foundation

public struct HTTPClient {
    public init() {}

    public func get(_ url: URL) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(from: url)
    }
}
