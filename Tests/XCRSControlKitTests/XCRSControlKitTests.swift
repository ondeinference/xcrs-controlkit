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

    func testAccessibilityNodeHasStableTransportShape() throws {
        let node = XCRSControlKitAccessibilityNode(
            type: "Button",
            label: "Play",
            name: "play-button",
            rawIdentifier: "play-button",
            rect: XCRSControlKitRect(x: 100, y: 200, width: 80, height: 40),
            enabled: true,
            selected: false,
            hittable: true
        )

        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(node)
        ) as? [String: Any]
        let rect = object?["rect"] as? [String: Any]

        XCTAssertEqual(object?["type"] as? String, "Button")
        XCTAssertEqual(object?["label"] as? String, "Play")
        XCTAssertEqual(object?["rawIdentifier"] as? String, "play-button")
        XCTAssertEqual(rect?["x"] as? Double, 100)
        XCTAssertEqual(rect?["width"] as? Double, 80)
        XCTAssertEqual((object?["children"] as? [[String: Any]])?.count, 0)
    }

    func testAccessibilityParserReadsSingleXCTestSnapshot() throws {
        let hierarchy = """
        Attributes: Application, 0x1, pid: 42, label: 'Viaplay'
        Element subtree:
         →Application, 0x1, pid: 42, label: 'Viaplay'
            Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
              Button, 0x3, {{576.0, 64.0}, {63.0, 32.0}}, identifier: 'Start', label: 'Hem', Focused
        Path to element:
         →Application, 0x1, pid: 42, label: 'Viaplay'
        """

        let root = try XCRSControlKitAccessibilityParser.parse(
            debugDescription: hierarchy
        )

        XCTAssertEqual(root.type, "Application")
        XCTAssertEqual(root.label, "Viaplay")
        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(root.children[1].type, "Button")
        XCTAssertEqual(root.children[1].label, "Hem")
        XCTAssertEqual(root.children[1].rawIdentifier, "Start")
        XCTAssertEqual(root.children[1].rect.x, 576)
        XCTAssertGreaterThan(root.children[1].depth ?? 0, root.depth ?? 0)
        XCTAssertEqual(root.children[1].selected, true)
    }
}
