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
    .package(url: "https://github.com/smbcloudXYZ/xcrs-controlkit.git", from: "0.1.0")
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

Runner implementations belong outside the Swift package target:

```text
Runners/
├── iOS/
├── tvOS/
├── watchOS/
├── visionOS/
└── macOS/
```

Each runner can import `XCRSControlKit` while using the appropriate Apple
frameworks and Xcode test target for its platform.

## Status

The package currently provides the public cross-platform contract. Native
runner projects and transport implementations are being added incrementally,
starting with iOS and tvOS.

## License

XCRSControlKit is available under the Apache License, Version 2.0.
