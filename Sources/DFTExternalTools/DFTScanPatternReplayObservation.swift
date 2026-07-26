public struct DFTScanPatternReplayObservation: Sendable, Hashable, Codable {
    public var faultID: String
    public var detected: Bool
    public var mismatchCount: Int

    public init(
        faultID: String,
        detected: Bool,
        mismatchCount: Int
    ) {
        self.faultID = faultID
        self.detected = detected
        self.mismatchCount = mismatchCount
    }
}
