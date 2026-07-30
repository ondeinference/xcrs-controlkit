# XCRSControlKit

XCRSControlKit is the shared Swift package contract for black-box automation
of Apple platforms. It provides stable target, capability, and request models
that can be used by native test runners and external automation clients.

The package is intentionally transport-neutral. Platform runners remain
separate Xcode projects because XCTest and UI testing require platform-specific
schemes, host applications, simulator destinations, signing, and entitlements.

## Supported platforms

- iOS and iPadOS
- tvOS
- watchOS
- visionOS
- macOS

## Installation

Add the package URL to an Xcode project or Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/ondeinference/xcrs-controlkit.git", from: "0.1.0")
]
```

Then import the library:

```swift
import XCRSControlKit

let capabilities = XCRSControlKitCapabilities.standard(for: .tvOS)
if capabilities.supports(.remoteButtons) {
    // Connect a tvOS runner and send remote-button requests.
}
```

## Runner projects

Runner implementations belong outside the Swift package target. All platforms
share one Xcode project generated with XcodeGen:

```text
Runners/
├── project.yml                     # XcodeGen spec
├── XCRSControlKitRunner.xcodeproj  # one project, per-platform targets/schemes
├── Shared/                         # transport + RPC server
├── iOS/                            # iOS / iPadOS host app
├── tvOS/                           # tvOS host app
├── visionOS/                       # visionOS host app
├── macOS/                          # macOS host app
└── watchOS/                        # watchOS host app
```

Each platform gets its own application and UI-test targets and a matching
scheme (`ControlKit-iOS`, `ControlKit-tvOS`, `ControlKit-visionOS`,
`ControlKit-macOS`, `ControlKit-watchOS`) while importing `XCRSControlKit` and
sharing the transport. See `Runners/README.md`.

## Status

The package provides the public cross-platform contract. Native ControlKit
runners currently support iOS, iPadOS, tvOS, visionOS, macOS, and watchOS.

## License

XCRSControlKit is available under the Apache License, Version 2.0.
