public struct DFTWaveformEvent: Sendable, Hashable, Codable {
    public var offsetPicoseconds: UInt64
    public var action: DFTWaveformAction

    public init(offsetPicoseconds: UInt64, action: DFTWaveformAction) {
        self.offsetPicoseconds = offsetPicoseconds
        self.action = action
    }
}
