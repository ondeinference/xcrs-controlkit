import Foundation

/// The Apple platform represented by a ControlKit runner.
public enum XCRSControlKitPlatform: String, Codable, CaseIterable, Sendable {
    case iOS
    case iPadOS
    case tvOS
    case watchOS
    case visionOS
    case macOS
}

/// An operation supported by a ControlKit runner.
public enum XCRSControlKitCapability: String, Codable, CaseIterable, Sendable {
    case accessibility
    case screenshot
    case appLifecycle
    case touch
    case textInput
    case swipe
    case orientation
    case remoteButtons
    case keyboard
    case pointer
    case spatialInteraction
    case pairedDevice
}

/// A simulator or device controlled by a runner.
public struct XCRSControlKitTarget: Codable, Equatable, Sendable {
    public let platform: XCRSControlKitPlatform
    public let identifier: String
    public let name: String?

    public init(
        platform: XCRSControlKitPlatform,
        identifier: String,
        name: String? = nil
    ) {
        self.platform = platform
        self.identifier = identifier
        self.name = name
    }
}

/// The capabilities advertised by a runner.
public struct XCRSControlKitCapabilities: Codable, Equatable, Sendable {
    public let platform: XCRSControlKitPlatform
    public let values: Set<XCRSControlKitCapability>

    public init(
        platform: XCRSControlKitPlatform,
        values: Set<XCRSControlKitCapability>
    ) {
        self.platform = platform
        self.values = values
    }

    public func supports(_ capability: XCRSControlKitCapability) -> Bool {
        values.contains(capability)
    }

    public static func standard(
        for platform: XCRSControlKitPlatform
    ) -> Self {
        let values: Set<XCRSControlKitCapability>

        switch platform {
        case .iOS, .iPadOS:
            values = [
                .accessibility,
                .screenshot,
                .appLifecycle,
                .touch,
                .textInput,
                .swipe,
                .orientation
            ]
        case .tvOS:
            values = [
                .accessibility,
                .screenshot,
                .appLifecycle,
                .remoteButtons
            ]
        case .watchOS:
            values = [
                .accessibility,
                .screenshot,
                .appLifecycle,
                .pairedDevice
            ]
        case .visionOS:
            values = [
                .accessibility,
                .screenshot,
                .appLifecycle,
                .spatialInteraction
            ]
        case .macOS:
            values = [
                .accessibility,
                .screenshot,
                .appLifecycle,
                .keyboard,
                .pointer
            ]
        }

        return Self(platform: platform, values: values)
    }
}

/// A screen-space rectangle reported by the accessibility hierarchy.
public struct XCRSControlKitRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// A transport-stable accessibility element returned by `device.dump.ui`.
public struct XCRSControlKitAccessibilityNode: Codable, Equatable, Sendable {
    public let type: String
    public let label: String?
    public let name: String?
    public let value: String?
    public let placeholderValue: String?
    public let rawIdentifier: String?
    public let rect: XCRSControlKitRect
    public let depth: Int?
    public let enabled: Bool?
    public let selected: Bool?
    public let hittable: Bool?
    public let children: [XCRSControlKitAccessibilityNode]

    public init(
        type: String,
        label: String? = nil,
        name: String? = nil,
        value: String? = nil,
        placeholderValue: String? = nil,
        rawIdentifier: String? = nil,
        rect: XCRSControlKitRect,
        depth: Int? = nil,
        enabled: Bool? = nil,
        selected: Bool? = nil,
        hittable: Bool? = nil,
        children: [XCRSControlKitAccessibilityNode] = []
    ) {
        self.type = type
        self.label = label
        self.name = name
        self.value = value
        self.placeholderValue = placeholderValue
        self.rawIdentifier = rawIdentifier
        self.rect = rect
        self.depth = depth
        self.enabled = enabled
        self.selected = selected
        self.hittable = hittable
        self.children = children
    }
}

/// Converts XCTest's single-snapshot hierarchy into ControlKit nodes.
public enum XCRSControlKitAccessibilityParser {
    public static func parse(
        debugDescription: String
    ) throws -> XCRSControlKitAccessibilityNode {
        let lines = debugDescription.components(separatedBy: .newlines)
        guard
            let subtreeStart = lines.firstIndex(of: "Element subtree:"),
            let subtreeEnd = lines[subtreeStart...].firstIndex(of: "Path to element:")
        else {
            throw XCRSControlKitError.invalidRequest(
                "XCTest did not return an accessibility subtree"
            )
        }

        let nodes = lines[lines.index(after: subtreeStart)..<subtreeEnd]
            .compactMap(parseLine)
        guard let root = nodes.first else {
            throw XCRSControlKitError.invalidRequest(
                "XCTest returned an empty accessibility subtree"
            )
        }

        return XCRSControlKitAccessibilityNode(
            type: root.type,
            label: root.label,
            name: root.name,
            value: root.value,
            placeholderValue: root.placeholderValue,
            rawIdentifier: root.rawIdentifier,
            rect: root.rect,
            depth: root.depth,
            enabled: root.enabled,
            selected: root.selected,
            hittable: root.hittable,
            children: Array(nodes.dropFirst())
        )
    }

    private static func parseLine(
        _ line: String
    ) -> XCRSControlKitAccessibilityNode? {
        let indentation = line.prefix(while: { $0 == " " }).count
        var content = line.trimmingCharacters(in: .whitespaces)
        if content.first == "→" {
            content.removeFirst()
        }
        guard let typeEnd = content.firstIndex(of: ",") else {
            return nil
        }

        let type = String(content[..<typeEnd])
        let identifier = quotedAttribute("identifier", in: content)
        let rect = rectangle(in: content) ?? XCRSControlKitRect(
            x: 0,
            y: 0,
            width: 0,
            height: 0
        )
        return XCRSControlKitAccessibilityNode(
            type: type,
            label: quotedAttribute("label", in: content),
            name: identifier,
            value: quotedAttribute("value", in: content),
            placeholderValue: quotedAttribute("placeholderValue", in: content),
            rawIdentifier: identifier,
            rect: rect,
            depth: indentation / 2,
            enabled: !content.contains(", Disabled"),
            selected: content.contains(", Selected") || content.contains(", Focused")
        )
    }

    private static func rectangle(in line: String) -> XCRSControlKitRect? {
        let pattern = #"\{\{(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\},\s*\{(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)\}\}"#
        guard
            let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
            ),
            match.numberOfRanges == 5
        else {
            return nil
        }

        let values = (1..<5).compactMap { index -> Double? in
            guard let range = Range(match.range(at: index), in: line) else {
                return nil
            }
            return Double(line[range])
        }
        guard values.count == 4 else {
            return nil
        }
        return XCRSControlKitRect(
            x: values[0],
            y: values[1],
            width: values[2],
            height: values[3]
        )
    }

    private static func quotedAttribute(
        _ name: String,
        in line: String
    ) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\(escapedName): '(.*?)'(?=,|$)"
        guard
            let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
            ),
            let valueRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        let value = String(line[valueRange])
        return value.isEmpty ? nil : value
    }
}

/// A transport-neutral command sent to a runner.
public struct XCRSControlKitRequest: Codable, Equatable, Sendable {
    public let id: String
    public let method: String
    public let parameters: [String: String]

    public init(
        id: String = UUID().uuidString,
        method: String,
        parameters: [String: String] = [:]
    ) {
        self.id = id
        self.method = method
        self.parameters = parameters
    }
}

/// Errors shared by package consumers and platform runners.
public enum XCRSControlKitError: Error, Equatable, Sendable {
    case unsupportedPlatform(XCRSControlKitPlatform)
    case unsupportedCapability(XCRSControlKitCapability)
    case invalidRequest(String)
    case transport(String)
}
