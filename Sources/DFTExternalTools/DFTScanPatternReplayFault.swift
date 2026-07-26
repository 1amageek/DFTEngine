struct DFTScanPatternReplayFault: Sendable, Hashable {
    var faultID: String
    var hierarchicalSignalPath: String
    var stuckAtValue: Bool

    init(
        faultID: String,
        hierarchicalSignalPath: String,
        stuckAtValue: Bool
    ) {
        self.faultID = faultID
        self.hierarchicalSignalPath = hierarchicalSignalPath
        self.stuckAtValue = stuckAtValue
    }
}
