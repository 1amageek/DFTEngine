public struct DFTPatternAssignment: Sendable, Hashable, Codable {
    public var target: String
    public var symbols: String

    public init(target: String, symbols: String) {
        self.target = target
        self.symbols = symbols
    }
}
