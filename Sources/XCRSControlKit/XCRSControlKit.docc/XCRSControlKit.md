# ``XCRSControlKit``

Shared contracts for black-box automation of Apple platforms.

## Overview

XCRSControlKit keeps platform runner contracts independent from the Xcode
projects that execute XCTest and XCUITest automation. Consumers can discover a
runner's platform and capabilities, identify a target, and send transport-neutral
requests without depending on a particular runner implementation.

The package does not import XCTest or private Apple frameworks.
