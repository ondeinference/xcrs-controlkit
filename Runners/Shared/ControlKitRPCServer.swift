import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import XCTest
import XCRSControlKit

private struct JSONRPCRequest {
    let method: String
    let params: [String: Any]
    let id: Any?
}

@MainActor
final class ControlKitRPCServer {
    private static let protocolVersion = 1
    private static let supportedMethods = [
        "device.apps.launch",
        "device.apps.terminate",
        "device.capabilities",
        "device.dump.ui",
        "device.info",
        "device.io.button",
        "device.io.click",
        "device.io.spatial.tap",
        "device.io.tap",
        "device.io.text"
    ]

    private let port: UInt16
    private let host: String

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
            return try response(
                result: [
                    "platform": Self.platform.rawValue,
                    "capabilities": XCRSControlKitCapabilities.standard(for: Self.platform).values.map(\.rawValue).sorted(),
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
            if request.params["format"] as? String == "debug" {
                return try response(
                    result: ["description": application.debugDescription],
                    id: request.id
                )
            }
            let hierarchy = try accessibilityHierarchy(application)
            return try response(result: dictionary(hierarchy), id: request.id)
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

    private func foregroundApplication(_ params: [String: Any]) -> XCUIApplication {
        if let bundleIdentifier = params["bundleId"] as? String {
            return XCUIApplication(bundleIdentifier: bundleIdentifier)
        }
        return XCUIApplication()
    }

    private func accessibilityHierarchy(
        _ application: XCUIApplication
    ) throws -> XCRSControlKitAccessibilityNode {
        try XCRSControlKitAccessibilityParser.parse(
            debugDescription: application.debugDescription
        )
    }

    private func dictionary(_ node: XCRSControlKitAccessibilityNode) throws -> [String: Any] {
        let data = try JSONEncoder().encode(node)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RunnerError.invalidAccessibilityHierarchy
        }
        return object
    }

    #if !os(tvOS)
    private func tap(_ params: [String: Any]) throws {
        let x = try doubleParameter("x", params)
        let y = try doubleParameter("y", params)
        let application = foregroundApplication(params)
        let frame = application.frame
        let coordinate = application.coordinate(
            withNormalizedOffset: CGVector(
                dx: max(0, min(1, x / Double(frame.width))),
                dy: max(0, min(1, y / Double(frame.height)))
            )
        )
        coordinate.tap()
    }
    #endif

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
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let requestHandler: (HTTPMethod, String, Data) async -> Data
    private var requestHead: HTTPRequestHead?
    private var requestBody = Data()

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
}

private enum RunnerError: LocalizedError {
    case invalidAccessibilityHierarchy
    case invalidParameter(String)
    case unsupportedButton(String)
    case unsupportedInteraction(String)

    var errorDescription: String? {
        switch self {
        case .invalidAccessibilityHierarchy:
            return "Could not serialize the accessibility hierarchy"
        case .invalidParameter(let name):
            return "Missing or invalid parameter: \(name)"
        case .unsupportedButton(let button):
            return "Unsupported button: \(button)"
        case .unsupportedInteraction(let interaction):
            return "Unsupported interaction: \(interaction)"
        }
    }
}
