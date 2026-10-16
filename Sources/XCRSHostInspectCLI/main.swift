#if os(macOS)
import Foundation
import XCRSHostInspect

let result = HostInspectCommand.invoke(arguments: Array(CommandLine.arguments.dropFirst()))

if !result.standardOutput.isEmpty {
    FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
}
if !result.standardError.isEmpty {
    FileHandle.standardError.write(Data(result.standardError.utf8))
}

exit(result.exitCode)
#else

// The helper drives the macOS window server and Vision, so on any other
// platform it has nothing to do but fail.
exit(1)

#endif
