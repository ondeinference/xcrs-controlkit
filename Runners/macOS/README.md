# ControlKit macOS host app

This folder holds the macOS host application (`ControlKitRunnerApp.swift` and
`Assets.xcassets`) for the `ControlKit-macOS` target in the shared
`XCRSControlKitRunner.xcodeproj`.

macOS is pointer-driven: `device.io.click` performs an `XCUICoordinate` click and
`device.io.text` types through the keyboard, while raw `device.io.tap` (touch),
`home`, and orientation controls are intentionally unsupported. The JSON-RPC
transport and server live in `../Shared` and are compiled into the
`ControlKit-macOS-UITests` target.

The generated XCUITest runner ships sandboxed with only the network *client*
entitlement, so `ControlKit-macOS-UITests.entitlements` additionally grants
`com.apple.security.network.server`, allowing the runner to bind its local RPC
port. The targets sign locally (`CODE_SIGN_IDENTITY = "-"`), so no team or
provisioning profile is required to build and test.
