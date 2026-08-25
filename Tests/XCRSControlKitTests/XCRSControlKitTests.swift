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
            focused: false,
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
        Attributes: Application, 0x1, pid: 42, label: 'Sample App'
        Element subtree:
         →Application, 0x1, pid: 42, label: 'Sample App'
            Window (Main), 0x2, {{0.0, 0.0}, {1920.0, 1080.0}}
              Button, 0x3, {{576.0, 64.0}, {63.0, 32.0}}, identifier: 'Start', label: 'Hem', Focused
        Path to element:
         →Application, 0x1, pid: 42, label: 'Sample App'
        """

        let root = try XCRSControlKitAccessibilityParser.parse(
            debugDescription: hierarchy
        )

        XCTAssertEqual(root.type, "Application")
        XCTAssertEqual(root.label, "Sample App")
        XCTAssertEqual(root.children.count, 1)
        let window = try XCTUnwrap(root.children.first)
        XCTAssertEqual(window.type, "Window (Main)")
        let button = try XCTUnwrap(window.children.first)
        XCTAssertEqual(button.type, "Button")
        XCTAssertEqual(button.label, "Hem")
        XCTAssertEqual(button.rawIdentifier, "Start")
        XCTAssertEqual(button.rect.x, 576)
        XCTAssertEqual(root.depth, 0)
        XCTAssertEqual(window.depth, 1)
        XCTAssertEqual(button.depth, 2)
        XCTAssertEqual(button.selected, false)
        XCTAssertEqual(button.focused, true)
    }

    func testAccessibilityParserReadsQuotedAttributesAndStates() throws {
        let hierarchy = """
        Element subtree:
         →Application, 0x1, label: 'Disabled, Selected, Focused'
            Button, 0x2, label: 'O'Brien', Disabled, Selected, Focused
        Path to element:
        """

        let root = try XCRSControlKitAccessibilityParser.parse(
            debugDescription: hierarchy
        )

        XCTAssertEqual(root.label, "Disabled, Selected, Focused")
        let button = try XCTUnwrap(root.children.first)
        XCTAssertEqual(button.label, "O'Brien")
        XCTAssertEqual(button.enabled, false)
        XCTAssertEqual(button.selected, true)
        XCTAssertEqual(button.focused, true)
        XCTAssertEqual(root.enabled, true)
    }

    func testAccessibilityParserKeepsSiblingsAtTheSameIndentation() throws {
        let hierarchy = """
        Element subtree:
         →Application, 0x1
            Button, 0x2, label: 'First'
            Button, 0x3, label: 'Second'
        Path to element:
        """

        let root = try XCRSControlKitAccessibilityParser.parse(
            debugDescription: hierarchy
        )

        XCTAssertEqual(root.children.map(\.label), ["First", "Second"])
        XCTAssertTrue(root.children.allSatisfy(\.children.isEmpty))
    }

    func testAccessibilityParserReadsEscapedAndBraceTerminatedAttributes() throws {
        let hierarchy = """
        Element subtree:
         →Application, 0x1, label: 'Sample'}
            Button, 0x2, label: 'It\\'s ready', Selected
        Path to element:
        """

        let root = try XCRSControlKitAccessibilityParser.parse(
            debugDescription: hierarchy
        )

        XCTAssertEqual(root.label, "Sample")
        let button = try XCTUnwrap(root.children.first)
        XCTAssertEqual(button.label, "It\\'s ready")
        XCTAssertEqual(button.selected, true)
    }

    func testAccessibilityParserRejectsMultipleRootElements() {
        let hierarchy = """
        Element subtree:
         →Application, 0x1
         →Window, 0x2
        Path to element:
        """

        XCTAssertThrowsError(
            try XCRSControlKitAccessibilityParser.parse(
                debugDescription: hierarchy
            )
        ) { error in
            XCTAssertEqual(
                error as? XCRSControlKitError,
                .invalidRequest("XCTest returned multiple root accessibility elements")
            )
        }
    }
}
