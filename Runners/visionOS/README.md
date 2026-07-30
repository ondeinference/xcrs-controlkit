# ControlKit visionOS host app

This folder holds the visionOS host application (`ControlKitRunnerApp.swift` and
`Assets.xcassets`) for the `ControlKit-visionOS` target in the shared
`XCRSControlKitRunner.xcodeproj`.

visionOS is spatial: `device.io.spatial.tap` performs accessibility-driven
activation through an `XCUICoordinate` tap, while raw `device.io.tap`, `home`,
and orientation controls are intentionally unsupported. The JSON-RPC transport
and server live in `../Shared` and are compiled into the
`ControlKit-visionOS-UITests` target.
