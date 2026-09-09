import XCTest

final class ControlKitRunnerUITests: XCTestCase {
    // MARK: - Internal

    @MainActor
    func testRunAutomation() async throws {
        continueAfterFailure = true
        let server = ControlKitRPCServer()
        try await server.start()
    }
}
