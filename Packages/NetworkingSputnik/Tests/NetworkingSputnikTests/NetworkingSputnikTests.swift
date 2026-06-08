import Testing
@testable import NetworkingSputnik

@Suite("NetworkingSputnik basic tests")
struct NetworkingSputnikTests {
    @Test
    func createClient() throws {
        _ = HTTPClient()
        #expect(true)
    }
}
