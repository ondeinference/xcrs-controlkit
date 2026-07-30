import XCTest
@testable import XCRSControlKit

final class XCRSControlKitTests: XCTestCase {
    func testStandardCapabilitiesArePlatformSpecific() {
        let iOSCapabilities = XCRSControlKitCapabilities.standard(for: .iOS)
        let tvOSCapabilities = XCRSControlKitCapabilities.standard(for: .tvOS)

        XCTAssertTrue(iOSCapabilities.supports(.touch))
        XCTAssertFalse(iOSCapabilities.supports(.remoteButtons))
        XCTAssertTrue(tvOSCapabilities.supports(.remoteButtons))
        XCTAssertFalse(tvOSCapabilities.supports(.touch))
    }

    func testCapabilitiesAreCodable() throws {
        let capabilities = XCRSControlKitCapabilities.standard(for: .macOS)
        let encoded = try JSONEncoder().encode(capabilities)
        let decoded = try JSONDecoder().decode(
            XCRSControlKitCapabilities.self,
            from: encoded
        )

        XCTAssertEqual(decoded, capabilities)
    }

    func testRequestHasStableTransportShape() throws {
        let request = XCRSControlKitRequest(
            id: "request-1",
            method: "device.io.button",
            parameters: ["button": "select"]
        )

        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(request)
        ) as? [String: Any]

        XCTAssertEqual(object?["id"] as? String, "request-1")
        XCTAssertEqual(object?["method"] as? String, "device.io.button")
        XCTAssertEqual(
            (object?["parameters"] as? [String: String])?["button"],
            "select"
        )
    }
}
