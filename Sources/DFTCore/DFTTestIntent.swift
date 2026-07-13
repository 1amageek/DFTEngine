import Foundation

public struct DFTTestIntent: Sendable, Hashable, Codable {
    public var name: String
    public var modes: [String]
    public var testModeSignal: String
    public var scanEnableSignal: String

    public init(
        name: String,
        modes: [String],
        testModeSignal: String,
        scanEnableSignal: String
    ) {
        self.name = name
        self.modes = modes
        self.testModeSignal = testModeSignal
        self.scanEnableSignal = scanEnableSignal
    }
}
