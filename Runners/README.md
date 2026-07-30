# Platform runners

Platform runners are separate Xcode projects rather than SwiftPM targets.
They import the local `XCRSControlKit` package and expose XCTest or
XCUITest-specific automation over the runner transport.

Use one project per Apple platform so each runner can define its own schemes,
host app, deployment target, signing configuration, and platform capabilities.
