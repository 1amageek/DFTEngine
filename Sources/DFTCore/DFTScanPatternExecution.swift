import Foundation

public struct DFTScanPatternExecution: Sendable, Hashable, Codable {
    public var id: String
    public var faultIDs: [String]
    public var chains: [DFTScanChainStimulus]
    public var capture: DFTScanCapture

    public init(
        id: String,
        faultIDs: [String],
        chains: [DFTScanChainStimulus],
        capture: DFTScanCapture
    ) {
        self.id = id
        self.faultIDs = faultIDs
        self.chains = chains
        self.capture = capture
    }
}
