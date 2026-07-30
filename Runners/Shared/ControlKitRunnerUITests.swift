import XCTest

final class ControlKitRunnerUITests: XCTestCase {
    @MainActor
    func testRunAutomation() async throws {
        continueAfterFailure = true
        let server = ControlKitRPCServer()
        try await server.start()
    }
}
