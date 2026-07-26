import Foundation

public struct DFTCompressionConfiguration: Sendable, Hashable, Codable {
    public var enabled: Bool
    public var ratio: Double?
    public var scanInputSignals: [String]
    public var scanOutputSignals: [String]

    public init(
        enabled: Bool,
        ratio: Double? = nil,
        scanInputSignals: [String] = [],
        scanOutputSignals: [String] = []
    ) {
        self.enabled = enabled
        self.ratio = ratio
        self.scanInputSignals = scanInputSignals
        self.scanOutputSignals = scanOutputSignals
    }
}
