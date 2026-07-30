# ControlKit tvOS host app

This folder holds the tvOS host application (`ControlKitRunnerApp.swift` and
`Assets.xcassets`) for the `ControlKit-tvOS` target in the shared
`XCRSControlKitRunner.xcodeproj`.

tvOS is remote-driven: `device.io.button` maps to `XCUIRemote` presses and
touch/`home` are intentionally unsupported. The JSON-RPC transport and server
live in `../Shared` and are compiled into the `ControlKit-tvOS-UITests` target.
