import Foundation

/// The result of one `xcrs-host-inspect` invocation, returned instead of
/// exiting so the command surface stays testable.
public struct HostInspectInvocationResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

#if os(macOS)

import ApplicationServices
import CoreGraphics
import ImageIO
import Vision

/// Errors surfaced to the `xcrs-host-inspect` command line.
public enum HostInspectError: Error, CustomStringConvertible {
    /// The invocation itself is wrong, so the CLI answers with the usage text.
    case usage(String)
    /// The request was well formed but could not be carried out.
    case failure(String)

    public var description: String {
        switch self {
        case .usage(let message), .failure(let message):
            return message
        }
    }
}

/// Converts between the coordinate space a caller reasons about and image
/// pixels. A Retina screenshot is two pixels per point, so `--scale 2` accepts
/// and reports points; the default of `1` accepts and reports pixels.
public struct HostInspectScale: Equatable, Sendable {
    public let pixelsPerUnit: Double

    public init(pixelsPerUnit: Double) throws {
        guard pixelsPerUnit > 0, pixelsPerUnit.isFinite else {
            throw HostInspectError.usage("--scale must be a positive number")
        }
        self.pixelsPerUnit = pixelsPerUnit
    }

    private init(validated pixelsPerUnit: Double) {
        self.pixelsPerUnit = pixelsPerUnit
    }

    public static let pixels = HostInspectScale(validated: 1)

    public func pixels(fromUnits units: Double) -> Double {
        units * pixelsPerUnit
    }

    public func units(fromPixels pixels: Double) -> Double {
        pixels / pixelsPerUnit
    }

    public func units(fromPixels pixels: Int) -> Double {
        units(fromPixels: Double(pixels))
    }
}

public struct HostInspectRect: Codable, Equatable, Sendable {
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

/// The image a result was read from, in both pixels and caller units.
public struct HostInspectImage: Codable, Equatable, Sendable {
    public let path: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let scale: Double
    public let width: Double
    public let height: Double
}

public struct HostWindow: Codable, Equatable, Sendable {
    public let id: Int
    public let owner: String
    public let title: String
    public let layer: Int
    /// Screen points in the global display space, unaffected by `--scale`.
    public let bounds: HostInspectRect
}

public struct HostWindowList: Codable, Equatable, Sendable {
    public let windows: [HostWindow]
}

public struct HostRecognizedText: Codable, Equatable, Sendable {
    public let text: String
    public let confidence: Double
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

public struct HostOcrResult: Codable, Equatable, Sendable {
    public let image: HostInspectImage
    /// The languages the request was configured with; empty means Vision's
    /// own default.
    public let languages: [String]
    /// Reading order: top to bottom, then left to right.
    public let results: [HostRecognizedText]
}

public struct HostCropResult: Codable, Equatable, Sendable {
    public let image: HostInspectImage
    /// The requested rect, in caller units.
    public let rect: HostInspectRect
    public let out: String
    public let pixelWidth: Int
    public let pixelHeight: Int
}

public enum HostProbeAxis: String, Codable, Sendable {
    case row
    case column
}

public struct HostColorRun: Codable, Equatable, Sendable {
    /// Run extent in caller units.
    public let start: Double
    public let end: Double
    public let width: Double
    /// Quantised `#rrggbb`, so low-order noise does not split a surface.
    public let color: String
}

public struct HostPostureResult: Codable, Equatable, Sendable {
    /// The Device Hub window that was driven.
    public let window: String
    /// The posture button that was pressed.
    public let button: String
}

public struct HostProbeResult: Codable, Equatable, Sendable {
    public let image: HostInspectImage
    public let axis: HostProbeAxis
    /// The probed row (y) or column (x), in caller units.
    public let position: Double
    public let from: Double
    public let to: Double
    public let runs: [HostColorRun]
}

/// Reads a screenshot or the host window server. Every image coordinate in the
/// output is expressed in caller units; `windows` reports screen points.
public enum HostInspect {
    /// Vision reports bounding boxes in normalised space, so lines whose
    /// vertical centres differ by less than this are treated as one line.
    private static let readingOrderTolerance = 0.01
    private static let quantizationShift: UInt8 = 3

    public static func windows(owner: String?) throws -> HostWindowList {
        guard
            let entries = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            throw HostInspectError.failure("the window server did not return a window list")
        }

        var windows: [HostWindow] = []
        for entry in entries {
            let ownerName = entry[kCGWindowOwnerName as String] as? String ?? ""
            if let owner, !ownerName.lowercased().contains(owner.lowercased()) {
                continue
            }
            guard
                let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else {
                continue
            }

            windows.append(
                HostWindow(
                    id: entry[kCGWindowNumber as String] as? Int ?? 0,
                    owner: ownerName,
                    title: entry[kCGWindowName as String] as? String ?? "",
                    layer: entry[kCGWindowLayer as String] as? Int ?? 0,
                    bounds: HostInspectRect(
                        x: rect.origin.x,
                        y: rect.origin.y,
                        width: rect.size.width,
                        height: rect.size.height
                    )
                )
            )
        }

        windows.sort { ($0.layer, $0.id) < ($1.layer, $1.id) }
        return HostWindowList(windows: windows)
    }

    /// The Device Hub buttons that set a foldable simulator's hinge, by posture.
    static let devicePostureButtons = [
        "closed": "Closed",
        "partiallyOpen": "Partially Open",
        "open": "Open"
    ]

    /// Presses the hinge button in the Device Hub window for `device` through the
    /// macOS accessibility API. The window does not need to be in front. The
    /// calling process needs the Accessibility permission.
    public static func setDeviceHubPosture(device: String, posture: String) throws -> HostPostureResult {
        guard let label = devicePostureButtons[posture] else {
            throw HostInspectError.usage(
                "--posture must be one of \(devicePostureButtons.keys.sorted().joined(separator: ", ")), got \(posture)"
            )
        }
        guard AXIsProcessTrusted() else {
            throw HostInspectError.failure(
                "Accessibility access is required to press Device Hub buttons. Allow the app that runs xcrs in System Settings > Privacy & Security > Accessibility, then try again."
            )
        }

        // A command-line process gets no live NSWorkspace updates, so find Device
        // Hub's pid through the window server instead.
        let entries = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let hubs = Set(
            entries.compactMap { entry -> pid_t? in
                guard entry[kCGWindowOwnerName as String] as? String == "Device Hub" else { return nil }
                return (entry[kCGWindowOwnerPID as String] as? Int).map { pid_t($0) }
            }
        ).sorted()
        guard !hubs.isEmpty else {
            throw HostInspectError.failure("Device Hub is not running. Open it with the device's window visible, then try again.")
        }

        // Device Hub titles a simulator's window "<name> – <runtime>".
        var windows: [AXUIElement] = []
        for hub in hubs {
            let application = AXUIElementCreateApplication(hub)
            for window in axChildren(application, attribute: kAXWindowsAttribute) {
                let title = axString(window, kAXTitleAttribute)
                if title == device || (
                    title.hasPrefix(device)
                        && title.dropFirst(device.count).unicodeScalars.first
                            .map(CharacterSet.whitespaces.contains) == true
                ) {
                    windows.append(window)
                }
            }
        }
        guard windows.count == 1, let window = windows.first else {
            throw HostInspectError.failure(
                windows.isEmpty
                    ? "Device Hub has no open window for '\(device)'. Open the device in Device Hub, then try again."
                    : "Device Hub has \(windows.count) windows for '\(device)'; close the extras so the target is unambiguous."
            )
        }
        guard let button = findAXButton(in: window, description: label, depth: 0) else {
            throw HostInspectError.failure(
                "the '\(device)' window has no '\(label)' button; the device may not be foldable."
            )
        }
        let status = AXUIElementPerformAction(button, kAXPressAction as CFString)
        guard status == .success else {
            throw HostInspectError.failure("pressing '\(label)' failed (AXError \(status.rawValue))")
        }
        return HostPostureResult(window: axString(window, kAXTitleAttribute), button: label)
    }

    private static func axString(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return ""
        }
        return value as? String ?? ""
    }

    private static func axChildren(_ element: AXUIElement, attribute: String = kAXChildrenAttribute) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private static func findAXButton(in element: AXUIElement, description: String, depth: Int) -> AXUIElement? {
        if axString(element, kAXRoleAttribute) == kAXButtonRole,
            axString(element, kAXDescriptionAttribute) == description {
            return element
        }
        guard depth < 12 else { return nil }
        for child in axChildren(element) {
            if let found = findAXButton(in: child, description: description, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    public static func recognizeText(
        image path: String,
        scale: HostInspectScale,
        languages: [String]
    ) throws -> HostOcrResult {
        let image = try loadImage(at: path)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        if !languages.isEmpty {
            request.recognitionLanguages = languages
        }

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            throw HostInspectError.failure(
                "text recognition failed for \(path): \(error.localizedDescription)"
            )
        }

        let observations = request.results ?? []
        // Vision's origin is the bottom-left corner, so a larger midY is nearer
        // the top of the image.
        let ordered = observations.sorted { first, second in
            let firstMidY = first.boundingBox.midY
            let secondMidY = second.boundingBox.midY
            if abs(firstMidY - secondMidY) > readingOrderTolerance {
                return firstMidY > secondMidY
            }
            return first.boundingBox.minX < second.boundingBox.minX
        }

        let width = Double(image.width)
        let height = Double(image.height)
        let results = ordered.compactMap { observation -> HostRecognizedText? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return HostRecognizedText(
                text: candidate.string,
                confidence: Double(candidate.confidence),
                x: scale.units(fromPixels: box.minX * width),
                y: scale.units(fromPixels: (1 - box.maxY) * height),
                width: scale.units(fromPixels: box.width * width),
                height: scale.units(fromPixels: box.height * height)
            )
        }

        return HostOcrResult(
            image: describe(image, path: path, scale: scale),
            languages: languages,
            results: results
        )
    }

    public static func crop(
        image path: String,
        rect: HostInspectRect,
        scale: HostInspectScale,
        out: String
    ) throws -> HostCropResult {
        let image = try loadImage(at: path)
        let pixelRect = CGRect(
            x: scale.pixels(fromUnits: rect.x).rounded(),
            y: scale.pixels(fromUnits: rect.y).rounded(),
            width: scale.pixels(fromUnits: rect.width).rounded(),
            height: scale.pixels(fromUnits: rect.height).rounded()
        )
        guard pixelRect.width >= 1, pixelRect.height >= 1 else {
            throw HostInspectError.usage("crop rect is smaller than one pixel: \(describe(rect))")
        }
        guard
            pixelRect.minX >= 0, pixelRect.minY >= 0,
            pixelRect.maxX <= CGFloat(image.width), pixelRect.maxY <= CGFloat(image.height)
        else {
            throw HostInspectError.failure(
                "crop rect \(describe(rect)) is outside the "
                    + "\(image.width)x\(image.height) px image"
            )
        }
        guard let cropped = image.cropping(to: pixelRect) else {
            throw HostInspectError.failure("CoreGraphics refused to crop \(describe(pixelRect))")
        }

        let url = URL(fileURLWithPath: out)
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                "public.png" as CFString,
                1,
                nil
            )
        else {
            throw HostInspectError.failure("cannot write a PNG to \(out)")
        }
        CGImageDestinationAddImage(destination, cropped, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HostInspectError.failure("cannot write a PNG to \(out)")
        }

        return HostCropResult(
            image: describe(image, path: path, scale: scale),
            rect: rect,
            out: out,
            pixelWidth: cropped.width,
            pixelHeight: cropped.height
        )
    }

    public static func probe(
        image path: String,
        axis: HostProbeAxis,
        position: Double,
        from: Double?,
        to: Double?,
        scale: HostInspectScale
    ) throws -> HostProbeResult {
        let image = try loadImage(at: path)
        let extent = axis == .row ? image.height : image.width

        let positionPixel = Int(scale.pixels(fromUnits: position).rounded())
        guard positionPixel >= 0, positionPixel < extent else {
            throw HostInspectError.failure(
                "probe position \(position) is outside the "
                    + "\(axis == .row ? "height \(image.height)" : "width \(image.width)") px image"
            )
        }

        let startPixel = clamp(
            Int(scale.pixels(fromUnits: from ?? scale.units(fromPixels: 0)).rounded()),
            lower: 0,
            upper: extent
        )
        let endPixel = clamp(
            Int(scale.pixels(fromUnits: to ?? scale.units(fromPixels: extent)).rounded()),
            lower: 0,
            upper: extent
        )
        guard endPixel > startPixel else {
            throw HostInspectError.usage(
                "--from must be smaller than --to (got \(startPixel)px ..< \(endPixel)px)"
            )
        }

        let sampleCount = endPixel - startPixel
        let stripRect =
            axis == .row
            ? CGRect(x: startPixel, y: positionPixel, width: sampleCount, height: 1)
            : CGRect(x: positionPixel, y: startPixel, width: 1, height: sampleCount)
        // Sampling a one-pixel strip first is what makes the probe read the
        // requested line; drawing the whole image into a thin context would
        // average every other line into it.
        guard let strip = image.cropping(to: stripRect) else {
            throw HostInspectError.failure("CoreGraphics refused to crop \(describe(stripRect))")
        }

        let buffer = try rgbaPixels(
            of: strip,
            width: axis == .row ? sampleCount : 1,
            height: axis == .row ? 1 : sampleCount
        )
        let keys = (0..<sampleCount).map { index in
            quantize(
                red: buffer[index * 4],
                green: buffer[index * 4 + 1],
                blue: buffer[index * 4 + 2]
            )
        }

        let runs = groupRuns(keys).map { run in
            HostColorRun(
                start: scale.units(fromPixels: startPixel + run.start),
                end: scale.units(fromPixels: startPixel + run.end),
                width: scale.units(fromPixels: run.end - run.start),
                color: hexColor(run.key)
            )
        }

        return HostProbeResult(
            image: describe(image, path: path, scale: scale),
            axis: axis,
            position: position,
            from: scale.units(fromPixels: startPixel),
            to: scale.units(fromPixels: endPixel),
            runs: runs
        )
    }

    private static func loadImage(at path: String) throws -> CGImage {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw HostInspectError.failure("cannot open an image at \(path)")
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw HostInspectError.failure("cannot decode an image at \(path)")
        }
        return image
    }

    private static func describe(
        _ image: CGImage,
        path: String,
        scale: HostInspectScale
    ) -> HostInspectImage {
        HostInspectImage(
            path: path,
            pixelWidth: image.width,
            pixelHeight: image.height,
            scale: scale.pixelsPerUnit,
            width: scale.units(fromPixels: image.width),
            height: scale.units(fromPixels: image.height)
        )
    }

    /// Draws the image into a tightly packed RGBA8 buffer at the requested
    /// sampling size rather than at native resolution.
    private static func rgbaPixels(of image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                return false
            }
            context.interpolationQuality = .none
            // No flip transform here on purpose. A CGBitmapContext maps user
            // space from the bottom-left but lays the buffer out from the top
            // row down, so drawing an image straight in already yields a
            // top-down buffer: buffer row 0 is the image's top row, which is
            // the reading order the probe reports.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else {
            throw HostInspectError.failure("cannot sample a \(width)x\(height) region")
        }
        return buffer
    }

    /// Five bits per channel is enough to separate adjacent UI surfaces
    /// without splitting one surface on anti-aliasing.
    static func quantize(red: UInt8, green: UInt8, blue: UInt8) -> Int {
        Int(red >> quantizationShift) << 10
            | Int(green >> quantizationShift) << 5
            | Int(blue >> quantizationShift)
    }

    static func hexColor(_ key: Int) -> String {
        let red = (key >> 10) & 31
        let green = (key >> 5) & 31
        let blue = key & 31
        return String(format: "#%02x%02x%02x", red << 3, green << 3, blue << 3)
    }

    /// Collapses equal neighbours into half-open `[start, end)` runs.
    static func groupRuns(_ keys: [Int]) -> [(start: Int, end: Int, key: Int)] {
        var runs: [(start: Int, end: Int, key: Int)] = []
        for (index, key) in keys.enumerated() {
            if var last = runs.last, last.key == key {
                last.end = index + 1
                runs[runs.count - 1] = last
            } else {
                runs.append((start: index, end: index + 1, key: key))
            }
        }
        return runs
    }

    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        min(max(value, lower), upper)
    }

    private static func describe(_ rect: CGRect) -> String {
        "\(Int(rect.origin.x)),\(Int(rect.origin.y))"
            + " \(Int(rect.width))x\(Int(rect.height)) px"
    }

    private static func describe(_ rect: HostInspectRect) -> String {
        "\(rect.x),\(rect.y) \(rect.width)x\(rect.height)"
    }
}

/// Parses and runs the `xcrs-host-inspect` command line.
public enum HostInspectCommand {
    public static let usage = """
        xcrs-host-inspect <command> [options]

        Commands:
          windows [--owner <substring>]
              List on-screen windows with their screen-point bounds.
          ocr --image <png> [--scale <n>] [--language <tag>]...
              Recognise text and report it with coordinates.
          crop --image <png> --rect <x,y,w,h> --out <png> [--scale <n>]
              Write a region of an image to a new PNG.
          probe --image <png> (--row <y> | --column <x>) [--from <a>] [--to <b>] [--scale <n>]
              Report quantised colour runs along one line of an image.
          devicehub-posture --device <name> --posture <closed|partiallyOpen|open>
              Set a foldable simulator's hinge by pressing the button in its Device
              Hub window. Needs Device Hub running and the Accessibility permission.
          help
              Print this text.

        Coordinates are in image units. One unit is one pixel unless --scale is
        given, in which case a unit is 1/scale pixels (a Retina screenshot is
        --scale 2, so units are points).

        Output is JSON on stdout; exit code 2 means a usage error and 1 a
        failed operation.
        """

    public static func invoke(arguments: [String]) -> HostInspectInvocationResult {
        do {
            return HostInspectInvocationResult(
                exitCode: 0,
                standardOutput: try execute(try parse(arguments)) + "\n",
                standardError: ""
            )
        } catch let error as HostInspectError {
            switch error {
            case .usage(let message):
                return HostInspectInvocationResult(
                    exitCode: 2,
                    standardOutput: "",
                    standardError: "error: \(message)\n\n\(usage)\n"
                )
            case .failure(let message):
                return HostInspectInvocationResult(
                    exitCode: 1,
                    standardOutput: "",
                    standardError: "error: \(message)\n"
                )
            }
        } catch {
            return HostInspectInvocationResult(
                exitCode: 1,
                standardOutput: "",
                standardError: "error: \(error)\n"
            )
        }
    }

    enum Command: Equatable {
        case help
        case windows(owner: String?)
        case devicePosture(device: String, posture: String)
        case ocr(image: String, scale: HostInspectScale, languages: [String])
        case crop(image: String, rect: HostInspectRect, scale: HostInspectScale, out: String)
        case probe(
            image: String,
            axis: HostProbeAxis,
            position: Double,
            from: Double?,
            to: Double?,
            scale: HostInspectScale
        )
    }

    static func parse(_ arguments: [String]) throws -> Command {
        var scanner = ArgumentScanner(arguments: arguments)
        guard let name = scanner.next() else {
            throw HostInspectError.usage("a command is required")
        }

        switch name {
        case "help", "-h", "--help":
            try scanner.rejectRemaining()
            return .help
        case "windows":
            return .windows(owner: try scanner.options().owner)
        case "devicehub-posture":
            let options = try scanner.options()
            guard let device = options.device else {
                throw HostInspectError.usage("--device is required")
            }
            guard let posture = options.posture else {
                throw HostInspectError.usage("--posture is required")
            }
            return .devicePosture(device: device, posture: posture)
        case "ocr":
            let options = try scanner.options()
            return .ocr(
                image: try options.requiredImage(),
                scale: options.scale,
                languages: options.languages
            )
        case "crop":
            let options = try scanner.options()
            return .crop(
                image: try options.requiredImage(),
                rect: try options.requiredRect(),
                scale: options.scale,
                out: try options.requiredOut()
            )
        case "probe":
            let options = try scanner.options()
            let axis: HostProbeAxis
            let position: Double
            switch (options.row, options.column) {
            case (let row?, nil):
                axis = .row
                position = row
            case (nil, let column?):
                axis = .column
                position = column
            case (nil, nil):
                throw HostInspectError.usage("probe needs --row or --column")
            case (_?, _?):
                throw HostInspectError.usage("probe takes either --row or --column, not both")
            }
            return .probe(
                image: try options.requiredImage(),
                axis: axis,
                position: position,
                from: options.from,
                to: options.to,
                scale: options.scale
            )
        default:
            throw HostInspectError.usage("unknown command \(name)")
        }
    }

    private static func execute(_ command: Command) throws -> String {
        switch command {
        case .help:
            return usage
        case .windows(let owner):
            return try encode(HostInspect.windows(owner: owner))
        case .devicePosture(let device, let posture):
            return try encode(HostInspect.setDeviceHubPosture(device: device, posture: posture))
        case .ocr(let image, let scale, let languages):
            return try encode(
                HostInspect.recognizeText(image: image, scale: scale, languages: languages)
            )
        case .crop(let image, let rect, let scale, let out):
            return try encode(
                HostInspect.crop(image: image, rect: rect, scale: scale, out: out)
            )
        case .probe(let image, let axis, let position, let from, let to, let scale):
            return try encode(
                HostInspect.probe(
                    image: image,
                    axis: axis,
                    position: position,
                    from: from,
                    to: to,
                    scale: scale
                )
            )
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let text = String(data: try encoder.encode(value), encoding: .utf8) else {
            throw HostInspectError.failure("could not render the result as UTF-8 JSON")
        }
        return text
    }
}

private struct CommandOptions {
    var image: String?
    var owner: String?
    var device: String?
    var posture: String?
    var out: String?
    var rect: String?
    var scale = HostInspectScale.pixels
    var row: Double?
    var column: Double?
    var from: Double?
    var to: Double?
    var languages: [String] = []

    func requiredImage() throws -> String {
        guard let image else {
            throw HostInspectError.usage("--image is required")
        }
        return image
    }

    func requiredOut() throws -> String {
        guard let out else {
            throw HostInspectError.usage("--out is required")
        }
        return out
    }

    func requiredRect() throws -> HostInspectRect {
        guard let rect else {
            throw HostInspectError.usage("--rect is required")
        }
        let parts = rect.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            throw HostInspectError.usage("--rect expects x,y,w,h, got \(rect)")
        }
        let values = try parts.map { part -> Double in
            let text = String(part).trimmingCharacters(in: .whitespaces)
            guard let value = Double(text), value.isFinite else {
                throw HostInspectError.usage("--rect values must be numbers, got \(rect)")
            }
            return value
        }
        guard values[2] > 0, values[3] > 0 else {
            throw HostInspectError.usage("--rect width and height must be positive, got \(rect)")
        }
        return HostInspectRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
}

private struct ArgumentScanner {
    private let arguments: [String]
    private var index = 0

    init(arguments: [String]) {
        self.arguments = arguments
    }

    mutating func next() -> String? {
        guard index < arguments.count else { return nil }
        defer { index += 1 }
        return arguments[index]
    }

    mutating func rejectRemaining() throws {
        if let extra = next() {
            throw HostInspectError.usage("unexpected argument \(extra)")
        }
    }

    mutating func options() throws -> CommandOptions {
        var options = CommandOptions()
        while let argument = next() {
            let (name, inlineValue) = ArgumentScanner.split(argument)
            switch name {
            case "--image":
                options.image = try value(name: name, inline: inlineValue)
            case "--owner":
                options.owner = try value(name: name, inline: inlineValue)
            case "--device":
                options.device = try value(name: name, inline: inlineValue)
            case "--posture":
                options.posture = try value(name: name, inline: inlineValue)
            case "--out":
                options.out = try value(name: name, inline: inlineValue)
            case "--rect":
                options.rect = try value(name: name, inline: inlineValue)
            case "--scale":
                options.scale = try HostInspectScale(
                    pixelsPerUnit: try number(name: name, inline: inlineValue)
                )
            case "--row":
                options.row = try number(name: name, inline: inlineValue)
            case "--column":
                options.column = try number(name: name, inline: inlineValue)
            case "--from":
                options.from = try number(name: name, inline: inlineValue)
            case "--to":
                options.to = try number(name: name, inline: inlineValue)
            case "--language":
                options.languages.append(try value(name: name, inline: inlineValue))
            case "-h", "--help":
                throw HostInspectError.usage("help is its own command")
            default:
                throw HostInspectError.usage("unknown option \(name)")
            }
        }
        return options
    }

    private mutating func value(name: String, inline: String?) throws -> String {
        if let inline { return inline }
        guard let following = next() else {
            throw HostInspectError.usage("\(name) needs a value")
        }
        return following
    }

    private mutating func number(name: String, inline: String?) throws -> Double {
        let raw = try value(name: name, inline: inline)
        guard let number = Double(raw), number.isFinite else {
            throw HostInspectError.usage("\(name) expects a number, got \(raw)")
        }
        return number
    }

    private static func split(_ argument: String) -> (name: String, inlineValue: String?) {
        guard let separator = argument.firstIndex(of: "=") else {
            return (argument, nil)
        }
        let name = String(argument[argument.startIndex..<separator])
        let value = String(argument[argument.index(after: separator)...])
        return (name, value)
    }
}

#else

/// Host inspection needs the macOS window server and Vision.
public enum HostInspectCommand {
    public static func invoke(arguments: [String]) -> HostInspectInvocationResult {
        HostInspectInvocationResult(
            exitCode: 1,
            standardOutput: "",
            standardError: "error: xcrs-host-inspect runs on macOS only\n"
        )
    }
}

#endif
