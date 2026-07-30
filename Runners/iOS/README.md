# ControlKit iOS host app

This folder holds the iOS / iPadOS host application (`ControlKitRunnerApp.swift`
and `Assets.xcassets`) for the `ControlKit-iOS` target in the shared
`XCRSControlKitRunner.xcodeproj`.

Touch input is delivered through `XCUICoordinate` taps; the `home` button maps
to `XCUIDevice`. The JSON-RPC transport and server live in `../Shared` and are
compiled into the `ControlKit-iOS-UITests` target.
