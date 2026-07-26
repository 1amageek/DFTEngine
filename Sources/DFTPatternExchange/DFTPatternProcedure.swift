public struct DFTPatternProcedure: Sendable, Hashable, Codable {
    public var name: String
    public var cycles: [DFTPatternCycle]

    public init(name: String, cycles: [DFTPatternCycle]) {
        self.name = name
        self.cycles = cycles
    }
}
