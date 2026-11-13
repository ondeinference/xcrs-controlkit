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

    /// Lines as XCTest prints them for a WebKit (Tauri) window on macOS: controls
    /// carry `title`, static text an unquoted trailing `value`.
    func testAccessibilityParserReadsMacOSTitlesAndUnquotedValues() throws {
        let hierarchy = """
        Element subtree:
         →Application, 0x1, pid: 52989, title: 'SplitFire AI', Disabled
            Window (Main), 0x2, {{356.0, 107.0}, {800.0, 600.0}}, title: 'SplitFire AI', Disabled
              StaticText, 0x3, {{440.0, 270.0}, {139.0, 17.0}}, value: No file selected
              Button, 0x4, {{950.0, 256.0}, {122.0, 45.0}}, title: 'CHOOSE FILE'
              Button, 0x5, {{420.0, 618.0}, {672.0, 61.0}}, title: 'SEPARATE', Disabled
              StaticText, 0x6, {{1.0, 2.0}, {3.0, 4.0}}, value: 01 — SOURCE AUDIO, Disabled
              Button, 0x7, {{1.0, 2.0}, {3.0, 4.0}}, identifier: 'close', label: 'Close', title: 'Ignored'
        Path to element:
        """

        let root = try XCRSControlKitAccessibilityParser.parse(
            debugDescription: hierarchy
        )

        XCTAssertEqual(root.label, "SplitFire AI")
        let window = try XCTUnwrap(root.children.first)
        XCTAssertEqual(window.label, "SplitFire AI")
        XCTAssertEqual(window.enabled, false)
        let children = window.children
        XCTAssertEqual(children.count, 5)
        XCTAssertEqual(children[0].value, "No file selected")
        XCTAssertNil(children[0].label)
        XCTAssertEqual(children[1].label, "CHOOSE FILE")
        XCTAssertEqual(children[1].rect, XCRSControlKitRect(x: 950, y: 256, width: 122, height: 45))
        XCTAssertEqual(children[2].label, "SEPARATE")
        XCTAssertEqual(children[2].enabled, false)
        XCTAssertEqual(children[3].value, "01 — SOURCE AUDIO")
        XCTAssertEqual(children[3].enabled, false)
        XCTAssertEqual(children[4].label, "Close", "an explicit label wins over title")
    }

    func testAccessibilityParserIgnoresValueSeparatorInsideQuotedTitle() throws {
        let hierarchy = """
        Element subtree:
         →Application, 0x1, pid: 1
            Window (Main), 0x2, {{0.0, 0.0}, {10.0, 10.0}}
              StaticText, 0x3, {{0.0, 0.0}, {1.0, 1.0}}, title: 'Total, value: n/a'
              StaticText, 0x4, {{0.0, 0.0}, {1.0, 1.0}}, title: 'Volume', value: 50%
        Path to element:
        """

        let root = try XCRSControlKitAccessibilityParser.parse(
            debugDescription: hierarchy
        )
        let window = try XCTUnwrap(root.children.first)
        let children = window.children
        XCTAssertEqual(children[0].label, "Total, value: n/a")
        XCTAssertNil(children[0].value, "a `, value: ` inside a quoted title is not a value attribute")
        XCTAssertEqual(children[1].label, "Volume")
        XCTAssertEqual(children[1].value, "50%", "a real unquoted value outside quotes is still read")
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
