import DFTCLIKit
import Darwin
import Foundation

@main
enum DFTCLI {
    static func main() async {
        do {
            let exitCode = try await DFTCLICommand().run(
                arguments: Array(CommandLine.arguments.dropFirst())
            )
            Darwin.exit(Int32(exitCode))
        } catch {
            StandardDFTCLIOutputWriter().writeError(error.localizedDescription)
            Darwin.exit(1)
        }
    }
}
