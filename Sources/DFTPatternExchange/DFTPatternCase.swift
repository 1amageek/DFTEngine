public struct DFTPatternCase: Sendable, Hashable, Codable {
    public var id: String
    public var procedureNames: [String]

    public init(id: String, procedureNames: [String]) {
        self.id = id
        self.procedureNames = procedureNames
    }
}
