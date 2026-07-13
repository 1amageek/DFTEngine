import Foundation

public struct DFTScanChain: Sendable, Hashable, Codable {
    public var id: String
    public var domainID: String
    public var index: Int
    public var estimatedElementCount: Int
    public var scanInSignal: String
    public var scanOutSignal: String

    public init(
        id: String,
        domainID: String,
        index: Int,
        estimatedElementCount: Int,
        scanInSignal: String,
        scanOutSignal: String
    ) {
        self.id = id
        self.domainID = domainID
        self.index = index
        self.estimatedElementCount = estimatedElementCount
        self.scanInSignal = scanInSignal
        self.scanOutSignal = scanOutSignal
    }
}
