import Foundation

public struct DFTScanPlan: Sendable, Hashable, Codable {
    public var architecture: DFTScanArchitecture
    public var chains: [DFTScanChain]
    public var totalEstimatedElementCount: Int
    public var maximumEstimatedChainLength: Int

    public init(
        architecture: DFTScanArchitecture,
        chains: [DFTScanChain],
        totalEstimatedElementCount: Int,
        maximumEstimatedChainLength: Int
    ) {
        self.architecture = architecture
        self.chains = chains
        self.totalEstimatedElementCount = totalEstimatedElementCount
        self.maximumEstimatedChainLength = maximumEstimatedChainLength
    }
}
