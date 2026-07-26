public struct DFTPatternTimingSet: Sendable, Hashable, Codable {
    public var name: String
    public var periodPicoseconds: UInt64
    public var waveforms: [DFTSignalWaveform]

    public init(
        name: String,
        periodPicoseconds: UInt64,
        waveforms: [DFTSignalWaveform]
    ) {
        self.name = name
        self.periodPicoseconds = periodPicoseconds
        self.waveforms = waveforms
    }
}
