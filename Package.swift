// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "XCRSControlKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "XCRSControlKit",
            targets: ["XCRSControlKit"]
        ),
        .library(
            name: "XCRSHostInspect",
            targets: ["XCRSHostInspect"]
        ),
        .executable(
            name: "xcrs-host-inspect",
            targets: ["XCRSHostInspectCLI"]
        )
    ],
    targets: [
        .target(name: "XCRSControlKit"),
        .target(name: "XCRSHostInspect"),
        .executableTarget(
            name: "XCRSHostInspectCLI",
            dependencies: ["XCRSHostInspect"]
        ),
        .testTarget(
            name: "XCRSControlKitTests",
            dependencies: ["XCRSControlKit"]
        ),
        .testTarget(
            name: "XCRSHostInspectTests",
            dependencies: ["XCRSHostInspect"],
            resources: [.copy("Fixtures")]
        )
    ]
)
