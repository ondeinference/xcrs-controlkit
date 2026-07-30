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
