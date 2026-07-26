public struct DFTPatternSignal: Sendable, Hashable, Codable {
    public var name: String
    public var direction: DFTPatternSignalDirection

    public init(name: String, direction: DFTPatternSignalDirection) {
        self.name = name
        self.direction = direction
    }
}
