public struct DFTPatternSignalGroup: Sendable, Hashable, Codable {
    public var name: String
    public var signalNames: [String]

    public init(name: String, signalNames: [String]) {
        self.name = name
        self.signalNames = signalNames
    }
}
