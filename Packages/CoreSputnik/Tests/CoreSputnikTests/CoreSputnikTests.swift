import Testing
@testable import CoreSputnik

@Suite("CoreSputnik basic tests")
struct CoreSputnikTests {
    @Test
    func versionIsNonEmpty() throws {
        #expect(!SputnikVersion.current.isEmpty)
    }
}
