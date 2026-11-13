import Foundation
import ImageIO
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
        "device.apps.activate",
        "device.apps.launch",
        "device.apps.terminate",
        "device.capabilities",
        "device.dump.ui",
        "device.hinge.get",
        "device.info",
        "device.io.button",
        "device.io.click",
        "device.io.drag",
        "device.io.key",
        "device.io.orientation.get",
        "device.io.orientation.set",
        "device.io.scroll",
        "device.io.spatial.tap",
        "device.io.swipe",
        "device.io.tap",
        "device.io.text",
        "device.screenshot",
        "device.ui.tap",
        "device.window.resize"
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
            let target = try requiredApplication(request.params)
            let (hierarchy, debugDescription) = try accessibilityHierarchy(
                target.application,
                name: target.name
            )
            var result = try dictionary(hierarchy)
            if (request.params["raw"] as? Bool) == true {
                result["debugDescription"] = debugDescription
            }
            return try response(result: result, id: request.id)
        case "device.ui.tap":
            let target = try requiredApplication(request.params)
            let element = try stringParameter("element", request.params)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !element.isEmpty else {
                throw RunnerError.invalidParameter("element")
            }
            let elementType: XCUIElement.ElementType
            if let typeName = request.params["type"] as? String, !typeName.isEmpty {
                guard let resolved = Self.elementTypes[typeName.lowercased()] else {
                    throw RunnerError.invalidParameter("type")
                }
                elementType = resolved
            } else {
                elementType = .any
            }
            let index = (request.params["index"] as? NSNumber)?.intValue
            try tapElement(
                named: element,
                ofType: elementType,
                index: index,
                in: target.application,
                name: target.name
            )
            return try response(result: ["success": true], id: request.id)
        case "device.apps.launch":
            try requiredApplication(request.params).application.launch()
            return try response(result: ["success": true], id: request.id)
        case "device.apps.activate":
            // Unlike launch, activate leaves an already-running app alone and only
            // brings it to the foreground. launch() on an app that something else
            // started (Finder, `open`, a second copy at another path) can block
            // for minutes and then fail with "does not have a process ID".
            let application = try requiredApplication(request.params).application
            application.activate()
            return try response(
                result: ["success": true, "state": Self.stateName(application.state)],
                id: request.id
            )
        case "device.apps.terminate":
            try requiredApplication(request.params).application.terminate()
            return try response(result: ["success": true], id: request.id)
        case "device.screenshot":
            return try response(result: screenshot(request.params), id: request.id)
        case "device.io.drag":
            #if os(macOS)
            try drag(request.params)
            return try response(result: ["success": true], id: request.id)
            #else
            throw RunnerError.unsupportedInteraction("pointer drag")
            #endif
        case "device.io.scroll":
            #if os(macOS)
            try scroll(request.params)
            return try response(result: ["success": true], id: request.id)
            #else
            throw RunnerError.unsupportedInteraction("scroll wheel")
            #endif
        case "device.io.key":
            #if os(macOS)
            try typeKey(request.params)
            return try response(result: ["success": true], id: request.id)
            #else
            throw RunnerError.unsupportedInteraction("keyboard shortcut")
            #endif
        case "device.window.resize":
            #if os(macOS)
            return try response(result: resizeWindow(request.params), id: request.id)
            #else
            throw RunnerError.unsupportedInteraction("window resize")
            #endif
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
            application(request.params).typeText(text)
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

    /// Resolves the app a request targets.
    ///
    /// On macOS `path` wins over `bundleId`: a bundle identifier resolves through
    /// LaunchServices, which picks one copy when several are installed (an App
    /// Store build in /Applications and a staged build elsewhere, say), and the
    /// runner then reports the copy you actually started as "not in the
    /// foreground". A path names exactly one bundle.
    private func application(_ params: [String: Any]) -> XCUIApplication {
        #if os(macOS)
        if let path = params["path"] as? String, !path.isEmpty {
            return XCUIApplication(url: URL(fileURLWithPath: path))
        }
        #endif
        if let bundleIdentifier = params["bundleId"] as? String, !bundleIdentifier.isEmpty {
            return XCUIApplication(bundleIdentifier: bundleIdentifier)
        }
        return XCUIApplication()
    }

    /// Like `application(_:)`, but the request must name the app.
    private func requiredApplication(
        _ params: [String: Any]
    ) throws -> (application: XCUIApplication, name: String) {
        #if os(macOS)
        if let path = params["path"] as? String, !path.isEmpty {
            return (application(params), path)
        }
        #endif
        let bundleIdentifier = try stringParameter("bundleId", params)
        return (XCUIApplication(bundleIdentifier: bundleIdentifier), bundleIdentifier)
    }

    private func accessibilityHierarchy(
        _ application: XCUIApplication,
        name: String
    ) throws -> (XCRSControlKitAccessibilityNode, String) {
        guard application.state == .runningForeground else {
            throw RunnerError.applicationNotInForeground(name)
        }
        let debugDescription = application.debugDescription
        guard application.state == .runningForeground else {
            throw RunnerError.applicationNotInForeground(name)
        }
        let hierarchy = try XCRSControlKitAccessibilityParser.parse(
            debugDescription: debugDescription
        )
        return (hierarchy, debugDescription)
    }

    /// Element types `device.ui.tap` can narrow a match to, by the names
    /// `device.dump.ui` reports in `type`.
    private static let elementTypes: [String: XCUIElement.ElementType] = [
        "button": .button,
        "link": .link,
        "statictext": .staticText,
        "textfield": .textField,
        "securetextfield": .secureTextField,
        "textview": .textView,
        "searchfield": .searchField,
        "checkbox": .checkBox,
        "radiobutton": .radioButton,
        "switch": .switch,
        "toggle": .toggle,
        "slider": .slider,
        "image": .image,
        "cell": .cell,
        "menuitem": .menuItem,
        "menubaritem": .menuBarItem,
        "popupbutton": .popUpButton,
        "tab": .tab,
        "other": .other
    ]

    private func tapElement(
        named element: String,
        ofType elementType: XCUIElement.ElementType,
        index: Int?,
        in application: XCUIApplication,
        name: String
    ) throws {
        guard application.state == .runningForeground else {
            throw RunnerError.applicationNotInForeground(name)
        }
        // macOS controls usually carry their text as `title` (a button's caption),
        // not `label`, so match it too there.
        #if os(macOS)
        let predicate = NSPredicate(
            format: "label == %@ OR identifier == %@ OR value == %@ OR title == %@",
            element,
            element,
            element,
            element
        )
        #else
        let predicate = NSPredicate(
            format: "label == %@ OR identifier == %@ OR value == %@",
            element,
            element,
            element
        )
        #endif
        // Web views repeat a control's text on the control and on the static
        // text inside it (and often on a nav link too), so callers can narrow
        // by type, or pick one of several matches by index (document order).
        let matches = application.descendants(matching: elementType).matching(predicate)
        let matchCount = matches.count
        guard matchCount > 0 else {
            throw RunnerError.elementNotFound(element)
        }
        if let index {
            guard index >= 0, index < matchCount else {
                throw RunnerError.invalidParameter("index")
            }
            try activate(matches.element(boundBy: index), named: element)
            return
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
        let application = application(params)
        guard application.state != .notRunning else {
            throw RunnerError.applicationNotRunning(
                (params["path"] as? String) ?? (params["bundleId"] as? String) ?? "the app under test"
            )
        }
        return application
    }

    private static func stateName(_ state: XCUIApplication.State) -> String {
        switch state {
        case .notRunning: return "notRunning"
        #if !os(macOS)
        case .runningBackgroundSuspended: return "runningBackgroundSuspended"
        #endif
        case .runningBackground: return "runningBackground"
        case .runningForeground: return "runningForeground"
        default: return "unknown"
        }
    }

    /// PNG of the app's main window (`target: "window"`, the default when an app
    /// is named) or of the whole main screen (`target: "screen"`), base64-encoded.
    /// Pixel sizes are read back from the PNG, so they include the display scale.
    private func screenshot(_ params: [String: Any]) throws -> [String: Any] {
        let named = params["path"] != nil || params["bundleId"] != nil
        let target = (params["target"] as? String) ?? (named ? "window" : "screen")
        let png: Data
        switch target {
        case "screen":
            png = XCUIScreen.main.screenshot().pngRepresentation
        case "window":
            let application = try runningApplication(params)
            png = try mainWindow(of: application).screenshot().pngRepresentation
        default:
            throw RunnerError.invalidParameter("target")
        }
        var result: [String: Any] = ["png": png.base64EncodedString(), "target": target]
        if
            let source = CGImageSourceCreateWithData(png as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        {
            result["width"] = properties[kCGImagePropertyPixelWidth]
            result["height"] = properties[kCGImagePropertyPixelHeight]
        }
        return result
    }

    /// The app's largest on-screen window. `windows.firstMatch` is not enough on
    /// macOS: WebKit-based apps (Tauri, Electron) also own small hidden helper
    /// windows that can come first.
    private func mainWindow(of application: XCUIApplication) throws -> XCUIElement {
        let windows = application.windows.allElementsBoundByIndex.filter { window in
            let frame = window.frame
            return frame.width > 1 && frame.height > 1
        }
        guard let window = windows.max(by: { left, right in
            left.frame.width * left.frame.height < right.frame.width * right.frame.height
        }) else {
            throw RunnerError.noWindow
        }
        return window
    }

    #if os(macOS)
    /// Maps a screen point (the space `device.dump.ui` reports rects in) to a
    /// coordinate anchored on the window under it. The application element has
    /// no frame of its own on macOS, so it cannot be the anchor there.
    private func screenCoordinate(
        x: Double,
        y: Double,
        in application: XCUIApplication
    ) throws -> (coordinate: XCUICoordinate, window: XCUIElement) {
        let point = CGPoint(x: x, y: y)
        let windows = application.windows.allElementsBoundByIndex.filter { window in
            let frame = window.frame
            return frame.width > 1 && frame.height > 1
        }
        guard let window = windows.first(where: { $0.frame.contains(point) }) ?? windows.first else {
            throw RunnerError.noWindow
        }
        let origin = window.frame.origin
        let coordinate = window
            .coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: x - origin.x, dy: y - origin.y))
        return (coordinate, window)
    }

    private func drag(_ params: [String: Any]) throws {
        let application = try runningApplication(params)
        let x1 = try doubleParameter("x1", params)
        let y1 = try doubleParameter("y1", params)
        let start = try screenCoordinate(x: x1, y: y1, in: application).coordinate
        // Anchor the end on the same window as the start, so a drag that leaves
        // the window (resizing it, dropping onto another app) still lands where
        // it was asked to.
        let end = start.withOffset(CGVector(
            dx: try doubleParameter("x2", params) - x1,
            dy: try doubleParameter("y2", params) - y1
        ))
        let holdMs = (try? doubleParameter("holdMs", params)) ?? 100
        start.press(forDuration: max(0.05, holdMs / 1000), thenDragTo: end)
    }

    private func scroll(_ params: [String: Any]) throws {
        let application = try runningApplication(params)
        let coordinate = try screenCoordinate(
            x: try doubleParameter("x", params),
            y: try doubleParameter("y", params),
            in: application
        ).coordinate
        coordinate.scroll(
            byDeltaX: (try? doubleParameter("dx", params)) ?? 0,
            deltaY: (try? doubleParameter("dy", params)) ?? 0
        )
    }

    private func typeKey(_ params: [String: Any]) throws {
        let name = try stringParameter("key", params)
        let key: String
        if let named = Self.namedKeys[name.lowercased()] {
            key = named.rawValue
        } else if name.count == 1 {
            key = name
        } else {
            throw RunnerError.unsupportedKey(name)
        }
        var flags: XCUIElement.KeyModifierFlags = []
        for modifier in (params["modifiers"] as? [String]) ?? [] {
            switch modifier.lowercased() {
            case "command", "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "option", "alt": flags.insert(.option)
            case "control", "ctrl": flags.insert(.control)
            case "function", "fn": flags.insert(.function)
            default: throw RunnerError.invalidParameter("modifiers")
            }
        }
        application(params).typeKey(key, modifierFlags: flags)
    }

    private static let namedKeys: [String: XCUIKeyboardKey] = [
        "return": .return,
        "enter": .enter,
        "escape": .escape,
        "tab": .tab,
        "space": .space,
        "delete": .delete,
        "backspace": .delete,
        "forwarddelete": .forwardDelete,
        "up": .upArrow,
        "down": .downArrow,
        "left": .leftArrow,
        "right": .rightArrow,
        "home": .home,
        "end": .end,
        "pageup": .pageUp,
        "pagedown": .pageDown
    ]

    /// Resizes the app's main window by dragging its bottom-right corner, then
    /// reports the frame the window actually ended up with. Windows enforce their
    /// own minimum and maximum sizes, and a full-screen window cannot be resized
    /// at all, so callers should compare the returned size with what they asked for.
    private func resizeWindow(_ params: [String: Any]) throws -> [String: Any] {
        let application = try runningApplication(params)
        let window = try mainWindow(of: application)
        let width = try doubleParameter("width", params)
        let height = try doubleParameter("height", params)
        guard width > 0, height > 0 else {
            throw RunnerError.invalidParameter(width > 0 ? "height" : "width")
        }
        // A window cannot grow past the screen edge, so move it first when asked:
        // drag a point in the title bar (clear of the traffic lights on the left)
        // until the window's top-left corner sits at x, y.
        if let x = try? doubleParameter("x", params), let y = try? doubleParameter("y", params) {
            let frame = window.frame
            let grab = window
                .coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: min(frame.width / 2, 160), dy: 8))
            grab.press(forDuration: 0.2, thenDragTo: grab.withOffset(CGVector(
                dx: x - frame.origin.x,
                dy: y - frame.origin.y
            )))
        }
        let before = window.frame
        // Grab two points inside the corner: far enough in to hit the resize
        // area rather than miss the window, close enough not to hit content.
        let corner = window
            .coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: before.width - 2, dy: before.height - 2))
        let target = corner.withOffset(CGVector(
            dx: width - before.width,
            dy: height - before.height
        ))
        corner.press(forDuration: 0.2, thenDragTo: target)
        let after = window.frame
        return [
            "x": after.origin.x,
            "y": after.origin.y,
            "width": after.width,
            "height": after.height,
            "requestedWidth": width,
            "requestedHeight": height,
            // The screen edge or the window's own size limits stopped the drag.
            "clamped": abs(after.width - width) > 1 || abs(after.height - height) > 1
        ]
    }
    #endif

    #if !os(tvOS)
    /// Maps a point in the application's frame to an `XCUICoordinate`, clamped to the frame.
    private func coordinate(x: Double, y: Double, in application: XCUIApplication) throws -> XCUICoordinate {
        #if os(macOS)
        return try screenCoordinate(x: x, y: y, in: application).coordinate
        #else
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
        #endif
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
    case noWindow
    case unsupportedButton(String)
    case unsupportedInteraction(String)
    case unsupportedKey(String)

    var errorDescription: String? {
        switch self {
        case .ambiguousElement(let element, let count):
            return "Multiple accessibility elements matched \(element): \(count). Narrow with type (e.g. Button) or pick one with index"
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
        case .noWindow:
            return "The application has no on-screen window"
        case .unsupportedKey(let key):
            return "Unsupported key: \(key). Use a single character or one of return, enter, escape, tab, space, delete, forwardDelete, up, down, left, right, home, end, pageUp, pageDown"
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
