import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import XCTest
import XCRSControlKit
#if os(iOS)
import UIKit
#endif

private struct JSONRPCRequest {
    let method: String
    let params: [String: Any]
    let id: Any?
}

@MainActor
final class ControlKitRPCServer {
    // MARK: - Internal

    init() {
        port = UInt16(ProcessInfo.processInfo.environment["CONTROLKIT_LISTEN_PORT"] ?? "12004") ?? 12004
        host = ProcessInfo.processInfo.environment["CONTROLKIT_LISTEN_HOST"] ?? "127.0.0.1"
    }

    func start() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            try? group.syncShutdownGracefully()
        }
        let requestHandler: (HTTPMethod, String, Data) async -> Data = { [self] method, path, body in
            if method == .GET && path == "/health" {
                return Data("OK".utf8)
            }
            return await handle(body)
        }
        let channel = try await ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(RPCHandler(requestHandler: requestHandler))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .bind(host: host, port: Int(port))
            .get()
        try await channel.closeFuture.get()
    }

    // MARK: - Private

    private static let protocolVersion = 1
    private static let supportedMethods = [
        "device.apps.launch",
        "device.apps.terminate",
        "device.capabilities",
        "device.dump.ui",
        "device.hinge.get",
        "device.info",
        "device.io.button",
        "device.io.click",
        "device.io.orientation.get",
        "device.io.orientation.set",
        "device.io.spatial.tap",
        "device.io.swipe",
        "device.io.tap",
        "device.io.text",
        "device.ui.tap"
    ]

    private static var platform: XCRSControlKitPlatform {
        #if os(tvOS)
        return .tvOS
        #elseif os(visionOS)
        return .visionOS
        #elseif os(macOS)
        return .macOS
        #elseif os(watchOS)
        return .watchOS
        #else
        return .iOS
        #endif
    }

    private let port: UInt16
    private let host: String

    private func handle(_ body: Data) async -> Data {
        do {
            if body == Data("health".utf8) {
                return try JSONSerialization.data(withJSONObject: ["status": "ok"])
            }

            guard
                let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
                let method = object["method"] as? String
            else {
                return try response(error: -32600, message: "Invalid Request", id: nil)
            }

            let request = JSONRPCRequest(
                method: method,
                params: object["params"] as? [String: Any] ?? [:],
                id: object["id"]
            )
            return try await dispatch(request)
        } catch {
            return (try? response(error: -32603, message: error.localizedDescription, id: nil)) ?? Data()
        }
    }

    private func dispatch(_ request: JSONRPCRequest) async throws -> Data {
        switch request.method {
        case "device.capabilities":
            var capabilities = XCRSControlKitCapabilities.standard(for: Self.platform).values
            if await hingeSnapshot() != nil {
                capabilities.insert(.hinge)
            }
            return try response(
                result: [
                    "platform": Self.platform.rawValue,
                    "capabilities": capabilities.map(\.rawValue).sorted(),
                    "methods": Self.supportedMethods
                ],
                id: request.id
            )
        case "device.info":
            return try response(
                result: [
                    "port": port,
                    "runner": "XCRSControlKit",
                    "protocolVersion": Self.protocolVersion,
                    "methods": Self.supportedMethods
                ],
                id: request.id
            )
        case "device.dump.ui":
            let bundleIdentifier = try stringParameter("bundleId", request.params)
            let application = XCUIApplication(bundleIdentifier: bundleIdentifier)
            let hierarchy = try accessibilityHierarchy(
                application,
                bundleIdentifier: bundleIdentifier
            )
            return try response(result: dictionary(hierarchy), id: request.id)
        case "device.ui.tap":
            let bundleIdentifier = try stringParameter("bundleId", request.params)
            let element = try stringParameter("element", request.params)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !element.isEmpty else {
                throw RunnerError.invalidParameter("element")
            }
            try tapElement(named: element, in: bundleIdentifier)
            return try response(result: ["success": true], id: request.id)
        case "device.apps.launch":
            let bundleIdentifier = try stringParameter("bundleId", request.params)
            let application = XCUIApplication(bundleIdentifier: bundleIdentifier)
            application.launch()
            return try response(result: ["success": true], id: request.id)
        case "device.apps.terminate":
            let bundleIdentifier = try stringParameter("bundleId", request.params)
            XCUIApplication(bundleIdentifier: bundleIdentifier).terminate()
            return try response(result: ["success": true], id: request.id)
        case "device.io.tap":
            #if os(tvOS) || os(visionOS) || os(macOS)
            throw RunnerError.unsupportedInteraction("touch")
            #else
            try tap(request.params)
            return try response(result: ["success": true], id: request.id)
            #endif
        case "device.io.click":
            #if os(macOS)
            try tap(request.params)
            return try response(result: ["success": true], id: request.id)
            #else
            throw RunnerError.unsupportedInteraction("pointer click")
            #endif
        case "device.io.spatial.tap":
            #if os(visionOS)
            try tap(request.params)
            return try response(result: ["success": true], id: request.id)
            #else
            throw RunnerError.unsupportedInteraction("spatial tap")
            #endif
        case "device.io.swipe":
            #if os(iOS)
            try swipe(request.params)
            return try response(result: ["success": true], id: request.id)
            #else
            throw RunnerError.unsupportedInteraction("swipe")
            #endif
        case "device.io.orientation.get":
            #if os(iOS)
            return try response(
                result: ["orientation": Self.orientationName(XCUIDevice.shared.orientation)],
                id: request.id
            )
            #else
            throw RunnerError.unsupportedInteraction("orientation")
            #endif
        case "device.io.orientation.set":
            #if os(iOS)
            let name = try stringParameter("orientation", request.params)
            guard let orientation = Self.orientation(named: name) else {
                throw RunnerError.invalidParameter("orientation")
            }
            XCUIDevice.shared.orientation = orientation
            return try response(result: ["success": true], id: request.id)
            #else
            throw RunnerError.unsupportedInteraction("orientation")
            #endif
        case "device.hinge.get":
            guard let hinge = await hingeSnapshot() else {
                return try response(result: ["status": "unsupported"], id: request.id)
            }
            return try response(
                result: ["status": hinge.status, "angle": hinge.angle],
                id: request.id
            )
        case "device.io.text":
            let text = try stringParameter("text", request.params)
            foregroundApplication(request.params).typeText(text)
            return try response(result: ["success": true], id: request.id)
        case "device.io.button":
            let button = try stringParameter("button", request.params)
            #if os(tvOS)
            let press: XCUIRemote.Button
            switch button {
            case "menu":
                press = .menu
            case "select":
                press = .select
            case "playPause":
                press = .playPause
            case "up":
                press = .up
            case "down":
                press = .down
            case "left":
                press = .left
            case "right":
                press = .right
            default:
                throw RunnerError.unsupportedButton(button)
            }
            XCUIRemote.shared.press(press)
            return try response(result: ["success": true], id: request.id)
            #elseif os(iOS)
            guard button == "home" else {
                throw RunnerError.unsupportedButton(button)
            }
            XCUIDevice.shared.press(.home)
            return try response(result: ["success": true], id: request.id)
            #else
            throw RunnerError.unsupportedButton(button)
            #endif
        default:
            return try response(error: -32601, message: "Method not found", id: request.id)
        }
    }

    private func foregroundApplication(_ params: [String: Any]) -> XCUIApplication {
        if let bundleIdentifier = params["bundleId"] as? String {
            return XCUIApplication(bundleIdentifier: bundleIdentifier)
        }
        return XCUIApplication()
    }

    private func accessibilityHierarchy(
        _ application: XCUIApplication,
        bundleIdentifier: String
    ) throws -> XCRSControlKitAccessibilityNode {
        guard application.state == .runningForeground else {
            throw RunnerError.applicationNotInForeground(bundleIdentifier)
        }
        let debugDescription = application.debugDescription
        guard application.state == .runningForeground else {
            throw RunnerError.applicationNotInForeground(bundleIdentifier)
        }
        return try XCRSControlKitAccessibilityParser.parse(
            debugDescription: debugDescription
        )
    }

    private func tapElement(named element: String, in bundleIdentifier: String) throws {
        let application = XCUIApplication(bundleIdentifier: bundleIdentifier)
        guard application.state == .runningForeground else {
            throw RunnerError.applicationNotInForeground(bundleIdentifier)
        }
        let predicate = NSPredicate(
            format: "label == %@ OR identifier == %@ OR value == %@",
            element,
            element,
            element
        )
        let matches = application.descendants(matching: .any).matching(predicate)
        let matchCount = matches.count
        guard matchCount > 0 else {
            throw RunnerError.elementNotFound(element)
        }
        guard matchCount == 1 else {
            throw RunnerError.ambiguousElement(element, matchCount)
        }
        try activate(matches.element(boundBy: 0), named: element)
    }

    private func activate(_ element: XCUIElement, named name: String) throws {
        #if os(tvOS)
        guard element.hasFocus else {
            throw RunnerError.elementNotFocused(name)
        }
        XCUIRemote.shared.press(.select)
        #else
        guard element.isHittable else {
            throw RunnerError.elementNotHittable(name)
        }
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
        #endif
    }

    private func dictionary(_ node: XCRSControlKitAccessibilityNode) throws -> [String: Any] {
        let data = try JSONEncoder().encode(node)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RunnerError.invalidAccessibilityHierarchy
        }
        return object
    }

    /// Like `foregroundApplication`, but fails cleanly when the app is not running.
    /// Querying a stopped application records an XCTest failure, which ends the
    /// runner's only test case and takes the server down with it.
    private func runningApplication(_ params: [String: Any]) throws -> XCUIApplication {
        let application = foregroundApplication(params)
        guard application.state != .notRunning else {
            throw RunnerError.applicationNotRunning((params["bundleId"] as? String) ?? "the app under test")
        }
        return application
    }

    #if !os(tvOS)
    /// Maps a point in the application's frame to an `XCUICoordinate`, clamped to the frame.
    private func coordinate(x: Double, y: Double, in application: XCUIApplication) throws -> XCUICoordinate {
        let frame = application.frame
        guard frame.width > 0, frame.height > 0 else {
            throw RunnerError.emptyFrame
        }
        return application.coordinate(
            withNormalizedOffset: CGVector(
                dx: max(0, min(1, x / Double(frame.width))),
                dy: max(0, min(1, y / Double(frame.height)))
            )
        )
    }

    private func tap(_ params: [String: Any]) throws {
        let x = try doubleParameter("x", params)
        let y = try doubleParameter("y", params)
        try coordinate(x: x, y: y, in: runningApplication(params)).tap()
    }
    #endif

    #if os(iOS)
    private func swipe(_ params: [String: Any]) throws {
        let application = try runningApplication(params)
        let start = try coordinate(
            x: try doubleParameter("x1", params),
            y: try doubleParameter("y1", params),
            in: application
        )
        let end = try coordinate(
            x: try doubleParameter("x2", params),
            y: try doubleParameter("y2", params),
            in: application
        )
        let durationMs = (try? doubleParameter("durationMs", params)) ?? 300
        start.press(forDuration: max(0.05, durationMs / 1000), thenDragTo: end)
    }

    private static func orientationName(_ orientation: UIDeviceOrientation) -> String {
        orientation.isLandscape ? "LANDSCAPE" : "PORTRAIT"
    }

    private static func orientation(named name: String) -> UIDeviceOrientation? {
        switch name.uppercased() {
        case "PORTRAIT":
            return .portrait
        case "LANDSCAPE":
            return .landscapeLeft
        default:
            return nil
        }
    }
    #endif

    private struct HingeSnapshot {
        let status: String
        let angle: Double
    }

    /// Reads the hinge, or returns nil when this platform or device reports none.
    private func hingeSnapshot() async -> HingeSnapshot? {
        #if os(iOS)
        if #available(iOS 27.1, *) {
            guard let hinge = await HingeReader.read() else { return nil }
            return HingeSnapshot(status: hinge.status, angle: hinge.angle)
        }
        #endif
        return nil
    }

    private func stringParameter(_ name: String, _ params: [String: Any]) throws -> String {
        guard let value = params[name] as? String, !value.isEmpty else {
            throw RunnerError.invalidParameter(name)
        }
        return value
    }

    private func doubleParameter(_ name: String, _ params: [String: Any]) throws -> Double {
        if let value = params[name] as? Double {
            return value
        }
        if let value = params[name] as? NSNumber {
            return value.doubleValue
        }
        throw RunnerError.invalidParameter(name)
    }

    private func response(result: [String: Any], id: Any?) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "result": result,
            "id": id ?? NSNull()
        ])
    }

    private func response(error code: Int, message: String, id: Any?) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message],
            "id": id ?? NSNull()
        ])
    }
}

private final class RPCHandler: ChannelInboundHandler {
    // MARK: - Internal

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    init(requestHandler: @escaping (HTTPMethod, String, Data) async -> Data) {
        self.requestHandler = requestHandler
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            requestHead = head
            requestBody.removeAll(keepingCapacity: true)
        case .body(var buffer):
            if let bytes = buffer.readBytes(length: buffer.readableBytes) {
                requestBody.append(contentsOf: bytes)
            }
        case .end:
            guard let requestHead else {
                context.close(promise: nil)
                return
            }

            let method = requestHead.method
            let path = requestHead.uri
            let body = requestBody
            Task {
                let responseBody = await requestHandler(method, path, body)
                context.eventLoop.execute {
                    var headers = HTTPHeaders()
                    headers.add(name: "Content-Type", value: "application/json")
                    headers.add(name: "Content-Length", value: "\(responseBody.count)")
                    headers.add(name: "Connection", value: "close")
                    let responseHead = HTTPResponseHead(
                        version: requestHead.version,
                        status: .ok,
                        headers: headers
                    )
                    var buffer = context.channel.allocator.buffer(capacity: responseBody.count)
                    buffer.writeBytes(responseBody)
                    context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
                    context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                    context.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { _ in
                        context.close(promise: nil)
                    }
                }
            }
        }
    }

    // MARK: - Private

    private let requestHandler: (HTTPMethod, String, Data) async -> Data
    private var requestHead: HTTPRequestHead?
    private var requestBody = Data()
}

private enum RunnerError: LocalizedError {
    case ambiguousElement(String, Int)
    case applicationNotRunning(String)
    case applicationNotInForeground(String)
    case invalidAccessibilityHierarchy
    case invalidParameter(String)
    case elementNotFound(String)
    case elementNotHittable(String)
    case emptyFrame
    case elementNotFocused(String)
    case unsupportedButton(String)
    case unsupportedInteraction(String)

    var errorDescription: String? {
        switch self {
        case .ambiguousElement(let element, let count):
            return "Multiple accessibility elements matched \(element): \(count)"
        case .applicationNotRunning(let application):
            return "Application \(application) is not running"
        case .emptyFrame:
            return "The application frame is empty, so there is nothing to tap"
        case .applicationNotInForeground(let bundleIdentifier):
            return "Application is not running in the foreground: \(bundleIdentifier)"
        case .invalidAccessibilityHierarchy:
            return "Could not serialize the accessibility hierarchy"
        case .invalidParameter(let name):
            return "Missing or invalid parameter: \(name)"
        case .elementNotFound(let element):
            return "No accessibility element matched: \(element)"
        case .elementNotHittable(let element):
            return "Accessibility element is not hittable: \(element)"
        case .elementNotFocused(let element):
            return "Accessibility element is not focused on tvOS: \(element)"
        case .unsupportedButton(let button):
            return "Unsupported button: \(button)"
        case .unsupportedInteraction(let interaction):
            return "Unsupported interaction: \(interaction)"
        }
    }
}

#if os(iOS)
/// `UIHinge` is only delivered through a `UIHingeInteraction` attached to a view,
/// so the reader hosts a one-off view in the runner's first window scene.
@available(iOS 27.1, *)
@MainActor
private enum HingeReader {
    static func read() async -> (status: String, angle: Double)? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return nil
        }
        let window = scene.windows.first ?? UIWindow(windowScene: scene)
        let view = UIView()
        window.addSubview(view)
        defer { view.removeFromSuperview() }

        let result: (status: String, angle: Double)? = await withCheckedContinuation { continuation in
            var resumed = false
            let finish: ((status: String, angle: Double)?) -> Void = { value in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }
            let interaction = UIHingeInteraction { _, update in
                guard let hinge = update.hinge else {
                    finish(nil)
                    return
                }
                finish((statusName(hinge.status), Double(hinge.angle)))
            }
            view.addInteraction(interaction)
            interaction.isEnabled = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                finish(nil)
            }
        }
        return result
    }

    private static func statusName(_ status: UIHinge.Status) -> String {
        switch status {
        case .closed: return "closed"
        case .partiallyOpen: return "partiallyOpen"
        case .fullyOpen: return "fullyOpen"
        default: return "unknown"
        }
    }
}
#endif
