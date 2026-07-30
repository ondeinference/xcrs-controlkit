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
        )
    ],
    targets: [
        .target(name: "XCRSControlKit"),
        .testTarget(
            name: "XCRSControlKitTests",
            dependencies: ["XCRSControlKit"]
        )
    ]
)
