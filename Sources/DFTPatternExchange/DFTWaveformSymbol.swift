public struct DFTWaveformSymbol: Sendable, Hashable, Codable {
    public var symbol: String
    public var events: [DFTWaveformEvent]

    public init(symbol: String, events: [DFTWaveformEvent]) {
        self.symbol = symbol
        self.events = events
    }
}
