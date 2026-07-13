import Foundation

public struct DFTScanDomain: Sendable, Hashable, Codable {
    public var id: String
    public var clockID: String
    public var resetID: String?
    public var chainCount: Int
    public var estimatedElementCount: Int
    public var maximumChainLength: Int?

    public init(
        id: String,
        clockID: String,
        resetID: String? = nil,
        chainCount: Int,
        estimatedElementCount: Int,
        maximumChainLength: Int? = nil
    ) {
        self.id = id
        self.clockID = clockID
        self.resetID = resetID
        self.chainCount = chainCount
        self.estimatedElementCount = estimatedElementCount
        self.maximumChainLength = maximumChainLength
    }
}
