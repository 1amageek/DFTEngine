import Foundation

public struct StandardDFTCLIOutputWriter: DFTCLIOutputWriting {
    public init() {}

    public func writeOutput(_ value: String) {
        FileHandle.standardOutput.write(Data((value + "\n").utf8))
    }

    public func writeError(_ value: String) {
        FileHandle.standardError.write(Data(("dft-engine: " + value + "\n").utf8))
    }
}
