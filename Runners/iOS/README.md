# XCRS ControlKit iOS runner

This is the first native runner owned by XCRS ControlKit. It is an Xcode UI
testing project, not a SwiftPM target, and imports the public
`XCRSControlKit` package for capability and request contracts.

The runner exposes a small localhost JSON-RPC server to the Rust `xcrs`
client using SwiftNIO's HTTP/1 server pipeline. It is an independent
ControlKit implementation with no private XCTest headers.
