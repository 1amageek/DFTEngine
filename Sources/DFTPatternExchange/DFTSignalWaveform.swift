public struct DFTSignalWaveform: Sendable, Hashable, Codable {
    public var signalName: String
    public var symbols: [DFTWaveformSymbol]

    public init(signalName: String, symbols: [DFTWaveformSymbol]) {
        self.signalName = signalName
        self.symbols = symbols
    }
}
