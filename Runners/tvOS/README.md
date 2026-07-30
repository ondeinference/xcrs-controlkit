# XCRS ControlKit tvOS runner

This is the native tvOS runner owned by XCRS ControlKit. It is an Xcode UI
testing project, not a SwiftPM target, and imports the public
`XCRSControlKit` package for capability and request contracts.

The runner exposes a localhost JSON-RPC server to the Rust `xcrs` client using
SwiftNIO's HTTP/1 server pipeline. tvOS remote buttons are handled through
`XCUIRemote`, with no private XCTest headers.
