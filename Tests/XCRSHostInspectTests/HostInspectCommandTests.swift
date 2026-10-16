#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO
import XCTest

@testable import XCRSHostInspect

/// The fixture is an 8x8 PNG whose top-left 4x4 quadrant is red and whose
/// remaining pixels are blue, which is what pins the coordinate conventions:
/// rows count down from the top, columns count right from the left.
final class HostInspectCommandTests: XCTestCase {
    private var outputDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("xcrs-host-inspect-tests", isDirectory: true)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
    }

    func testColumnProbeReadsFromTheTop() throws {
        let probe = try decode(
            HostProbeResult.self,
            from: try invoke(["probe", "--image", try fixture().path, "--column", "1"])
        )

        XCTAssertEqual(probe.axis, .column)
        XCTAssertEqual(probe.runs.map(\.color), ["#f80000", "#0000f8"])
        XCTAssertEqual(probe.runs.map(\.start), [0, 4])
        XCTAssertEqual(probe.runs.map(\.end), [4, 8])
        XCTAssertEqual(probe.runs.map(\.width), [4, 4])
    }

    func testRowProbeReadsFromTheLeft() throws {
        let probe = try decode(
            HostProbeResult.self,
            from: try invoke(["probe", "--image", try fixture().path, "--row", "1"])
        )

        XCTAssertEqual(probe.axis, .row)
        XCTAssertEqual(probe.runs.map(\.color), ["#f80000", "#0000f8"])
        XCTAssertEqual(probe.runs.map(\.start), [0, 4])
    }

    func testProbeHonoursFromAndTo() throws {
        let probe = try decode(
            HostProbeResult.self,
            from: try invoke(
                ["probe", "--image", try fixture().path, "--column", "1", "--from", "4", "--to", "8"]
            )
        )

        XCTAssertEqual(probe.from, 4)
        XCTAssertEqual(probe.to, 8)
        XCTAssertEqual(probe.runs.map(\.color), ["#0000f8"])
        XCTAssertEqual(probe.runs.map(\.start), [4])
        XCTAssertEqual(probe.runs.map(\.end), [8])
    }

    func testCropKeepsTheTopLeftOrigin() throws {
        let source = try fixture().path

        let topLeft = try temporaryFile(named: "crop-top-left.png")
        let result = try decode(
            HostCropResult.self,
            from: try invoke(
                ["crop", "--image", source, "--rect", "0,0,4,4", "--out", topLeft.path]
            )
        )
        XCTAssertEqual(result.pixelWidth, 4)
        XCTAssertEqual(result.pixelHeight, 4)
        XCTAssertEqual(try Set(pixelColors(of: topLeft)), ["#ff0000"])

        let bottomRight = try temporaryFile(named: "crop-bottom-right.png")
        _ = try invoke(
            ["crop", "--image", source, "--rect", "4,4,4,4", "--out", bottomRight.path]
        )
        XCTAssertEqual(try Set(pixelColors(of: bottomRight)), ["#0000ff"])
    }

    func testScaleConvertsUnitsToPixels() throws {
        // At --scale 4 the 8x8 fixture is 2x2 units, so the quadrant boundary
        // falls on the unit boundary at 1.
        let probe = try decode(
            HostProbeResult.self,
            from: try invoke(
                ["probe", "--image", try fixture().path, "--column", "0.5", "--scale", "4"]
            )
        )

        XCTAssertEqual(probe.image.pixelWidth, 8)
        XCTAssertEqual(probe.image.width, 2)
        XCTAssertEqual(probe.image.height, 2)
        XCTAssertEqual(probe.position, 0.5)
        XCTAssertEqual(probe.runs.map(\.start), [0, 1])
        XCTAssertEqual(probe.runs.map(\.end), [1, 2])
        XCTAssertEqual(probe.runs.map(\.color), ["#f80000", "#0000f8"])
    }

    func testScaleRejectsZero() {
        let result = HostInspectCommand.invoke(
            arguments: ["probe", "--image", "x.png", "--column", "1", "--scale", "0"]
        )
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.standardError.contains("--scale"))
    }

    func testProbeNeedsAnAxis() {
        let result = HostInspectCommand.invoke(arguments: ["probe", "--image", "x.png"])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertEqual(result.standardOutput, "")
        XCTAssertTrue(result.standardError.contains("--row or --column"))
        XCTAssertTrue(result.standardError.contains("xcrs-host-inspect"), "expected the usage text")
    }

    func testProbeRejectsBothAxes() {
        let result = HostInspectCommand.invoke(
            arguments: ["probe", "--image", "x.png", "--row", "1", "--column", "1"]
        )
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.standardError.contains("either --row or --column"))
    }

    func testMissingImageIsAUsageError() {
        let result = HostInspectCommand.invoke(arguments: ["ocr"])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.standardError.contains("--image is required"))
    }

    func testBadRectIsAUsageError() {
        let result = HostInspectCommand.invoke(
            arguments: ["crop", "--image", "x.png", "--rect", "1,2,3", "--out", "o.png"]
        )
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.standardError.contains("--rect expects x,y,w,h"))
    }

    func testUnknownOptionIsAUsageError() {
        let result = HostInspectCommand.invoke(arguments: ["windows", "--nope"])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.standardError.contains("unknown option --nope"))
    }

    func testUnknownCommandIsAUsageError() {
        let result = HostInspectCommand.invoke(arguments: ["snapshot"])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(result.standardError.contains("unknown command snapshot"))
    }

    func testHelpPrintsUsage() {
        let result = HostInspectCommand.invoke(arguments: ["help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.standardOutput.contains("xcrs-host-inspect"))
        XCTAssertTrue(result.standardError.isEmpty)
    }

    func testUnreadableImageFails() {
        let result = HostInspectCommand.invoke(
            arguments: [
                "crop", "--image", "/nonexistent/missing.png", "--rect", "0,0,1,1", "--out",
                temporaryFile(named: "unused.png").path,
            ]
        )
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.standardError.contains("cannot open an image"))
    }

    func testCropOutsideTheImageFails() throws {
        let result = HostInspectCommand.invoke(
            arguments: [
                "crop", "--image", try fixture().path, "--rect", "6,6,4,4", "--out",
                temporaryFile(named: "outside.png").path,
            ]
        )
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.standardError.contains("outside the 8x8 px image"))
    }

    func testWindowsReturnsAWindowList() throws {
        let list = try decode(
            HostWindowList.self,
            from: try invoke(["windows"])
        )
        XCTAssertTrue(
            list.windows.allSatisfy { $0.bounds.width >= 0 && $0.bounds.height >= 0 },
            "window bounds should never be negative"
        )

        let filtered = try decode(
            HostWindowList.self,
            from: try invoke(["windows", "--owner", "no-such-app-2a3f"])
        )
        XCTAssertTrue(filtered.windows.isEmpty, "the owner filter should exclude everything")
    }

    func testQuantizeCollapsesLowOrderBits() {
        XCTAssertEqual(
            HostInspect.quantize(red: 0xFF, green: 0x00, blue: 0x00),
            HostInspect.quantize(red: 0xF8, green: 0x07, blue: 0x07)
        )
        XCTAssertEqual(
            HostInspect.hexColor(HostInspect.quantize(red: 0xFF, green: 0x00, blue: 0x00)),
            "#f80000"
        )
    }

    func testGroupRunsCollapsesNeighbours() {
        let runs = HostInspect.groupRuns([1, 1, 2, 2, 2, 1])
        XCTAssertEqual(runs.map { $0.start }, [0, 2, 5])
        XCTAssertEqual(runs.map { $0.end }, [2, 5, 6])
        XCTAssertEqual(runs.map { $0.key }, [1, 2, 1])
    }

    func testInlineOptionValuesAreAccepted() throws {
        let probe = try decode(
            HostProbeResult.self,
            from: try invoke(["probe", "--image=\(try fixture().path)", "--column=1"])
        )
        XCTAssertEqual(probe.runs.count, 2)
    }

    private func invoke(_ arguments: [String]) throws -> String {
        let result = HostInspectCommand.invoke(arguments: arguments)
        XCTAssertEqual(result.exitCode, 0, result.standardError)
        return result.standardOutput
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func fixture() throws -> URL {
        try XCTUnwrap(
            Bundle.module.url(
                forResource: "top-left-red.png",
                withExtension: nil,
                subdirectory: "Fixtures"
            ),
            "the top-left-red.png fixture is missing from the test bundle"
        )
    }

    private func temporaryFile(named name: String) -> URL {
        outputDirectory.appendingPathComponent(name)
    }

    /// Reads every pixel of a PNG as raw hex, without quantisation, so the
    /// assertions above only fail for a real orientation or colour mistake.
    private func pixelColors(of url: URL) throws -> [String] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        buffer.withUnsafeMutableBytes { raw in
            guard
                let context = CGContext(
                    data: raw.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                return
            }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )
        }
        return stride(from: 0, to: buffer.count, by: 4).map { index in
            String(
                format: "#%02x%02x%02x",
                buffer[index],
                buffer[index + 1],
                buffer[index + 2]
            )
        }
    }
}

#endif
