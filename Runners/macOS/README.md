# ControlKit macOS host app

This folder holds the macOS host application (`ControlKitRunnerApp.swift` and
`Assets.xcassets`) for the `ControlKit-macOS` target in the shared
`XCRSControlKitRunner.xcodeproj`.

macOS is pointer-driven: `device.io.click` clicks, `device.io.drag` presses and
drags, `device.io.scroll` turns the scroll wheel, `device.io.text` types and
`device.io.key` presses a key with optional modifiers (`command`, `shift`,
`option`, `control`, `function`). Coordinates are screen points, the space
`device.dump.ui` reports rects in; the runner anchors them on the app window
under the point, because the application element itself has no frame on macOS.
`device.window.resize` moves and resizes the main window, and
`device.screenshot` captures it (or the whole screen) as a PNG. Raw
`device.io.tap` (touch), `device.io.swipe`, `home`, and orientation controls
are intentionally unsupported.

Every method that names an app accepts `path` (the `.app` bundle) as well as
`bundleId`. A bundle identifier resolves through LaunchServices, which picks
one copy when several are installed, so name the path when testing a build that
is not the one in `/Applications`. `device.apps.activate` foregrounds an app
that is already running; `device.apps.launch` on an app started outside the
runner can block for minutes and then fail with "does not have a process ID".

XCTest prints a macOS control's text as `title` and a static text's value
unquoted. `device.dump.ui` reports the title as `label` and reads the unquoted
value, and `device.ui.tap` matches titles, narrowed with `type` (for example
`Button`) or `index` when a web view repeats the same text. The JSON-RPC
transport and server live in `../Shared` and are compiled into the
`ControlKit-macOS-UITests` target.

The generated XCUITest runner ships sandboxed with only the network *client*
entitlement, so `ControlKit-macOS-UITests.entitlements` additionally grants
`com.apple.security.network.server`, allowing the runner to bind its local RPC
port. The targets sign locally (`CODE_SIGN_IDENTITY = "-"`), so no team or
provisioning profile is required to build and test.

`device.io.swipe`, `device.io.orientation.*` and `device.hinge.get` are not available on this runner.
