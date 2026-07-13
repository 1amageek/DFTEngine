import Foundation

public struct DFTExternalToolOutput: Sendable, Hashable {
    public var standardOutput: Data
    public var standardError: Data
    public var exitCode: Int32

    public init(
        standardOutput: Data,
        standardError: Data,
        exitCode: Int32
    ) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }
}
