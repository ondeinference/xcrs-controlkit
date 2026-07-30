# ControlKit watchOS host app

This folder holds the watchOS host application (`ControlKitRunnerApp.swift` and
`Assets.xcassets`) for the `ControlKit-watchOS` target in the shared
`XCRSControlKitRunner.xcodeproj`.

watchOS UI testing is supported from Xcode 26 onward (the platform ships
`XCUIAutomation.framework`). Touch input is delivered through `XCUICoordinate`
taps; `device.capabilities` reports the paired-device profile
(`accessibility`, `appLifecycle`, `pairedDevice`, `screenshot`), and pointer,
spatial, `home`, and remote-button interactions are intentionally unsupported.
The JSON-RPC transport and server live in `../Shared` and are compiled into the
`ControlKit-watchOS-UITests` target.
