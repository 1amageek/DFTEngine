import Foundation

public struct DFTScanReset: Sendable, Hashable, Codable {
    public var id: String
    public var signalName: String
    public var activeLevel: DFTSignalLevel
    public var asynchronous: Bool

    public init(
        id: String,
        signalName: String,
        activeLevel: DFTSignalLevel,
        asynchronous: Bool
    ) {
        self.id = id
        self.signalName = signalName
        self.activeLevel = activeLevel
        self.asynchronous = asynchronous
    }
}
