# ControlKit iOS host app

This folder holds the iOS / iPadOS host application (`ControlKitRunnerApp.swift`
and `Assets.xcassets`) for the `ControlKit-iOS` target in the shared
`XCRSControlKitRunner.xcodeproj`.

Touch input is delivered through `XCUICoordinate` taps; the `home` button maps
to `XCUIDevice`. Swipes use `XCUICoordinate.press(forDuration:thenDragTo:)`,
orientation maps `PORTRAIT`/`LANDSCAPE` to `XCUIDevice.orientation`, and on iOS
27.1 or later `device.hinge.get` reads `UIHinge` through a `UIHingeInteraction`.
The `hinge` capability is advertised only on a device that reports a hinge, such
as the iPhone Duo simulator. The JSON-RPC transport and server live in `../Shared` and are
compiled into the `ControlKit-iOS-UITests` target.
