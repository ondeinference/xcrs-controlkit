# Platform runners

All native runners live in a **single Xcode project**,
`XCRSControlKitRunner.xcodeproj`, generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). Each Apple platform has its
own application and UI-test targets plus a matching scheme, while the transport
and RPC logic are shared.

```text
Runners/
├── project.yml                     # XcodeGen spec (source of truth)
├── XCRSControlKitRunner.xcodeproj  # generated; do not hand-edit
├── Shared/                         # transport + RPC server, shared by all targets
│   ├── ControlKitRPCServer.swift
│   └── ControlKitRunnerUITests.swift
├── iOS/                            # iOS / iPadOS host app + assets
├── tvOS/                           # tvOS host app + assets
└── visionOS/                       # visionOS host app + assets
```

## Targets and schemes

| Scheme | App target | UI-test target | Platform |
|---|---|---|---|
| `ControlKit-iOS` | `ControlKit-iOS` | `ControlKit-iOS-UITests` | iOS / iPadOS |
| `ControlKit-tvOS` | `ControlKit-tvOS` | `ControlKit-tvOS-UITests` | tvOS |
| `ControlKit-visionOS` | `ControlKit-visionOS` | `ControlKit-visionOS-UITests` | visionOS |

Each UI-test target compiles the shared `Shared/` sources for its platform, so
platform behaviour is selected at compile time via `#if os(...)` in
`ControlKitRPCServer.swift`. Per-platform bundle identifiers, device families,
app icons, and deployment targets keep signing and packaging independent.

## Regenerating the project

After editing `project.yml` (or adding a platform folder), regenerate:

```sh
brew install xcodegen   # once
cd Runners
xcodegen generate
```

The generated `.xcodeproj` is committed so contributors without XcodeGen can
still open and build the runners; only structural changes require regeneration.
