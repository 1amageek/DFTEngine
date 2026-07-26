public struct DFTPatternCycle: Sendable, Hashable, Codable {
    public var timingSetName: String
    public var assignments: [DFTPatternAssignment]

    public init(
        timingSetName: String,
        assignments: [DFTPatternAssignment]
    ) {
        self.timingSetName = timingSetName
        self.assignments = assignments
    }
}
