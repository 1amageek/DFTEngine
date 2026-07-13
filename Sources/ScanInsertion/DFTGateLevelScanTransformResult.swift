import LogicIR

public struct DFTGateLevelScanTransformResult: Sendable, Hashable {
    public var snapshot: LogicDesignSnapshot
    public var transformedCellIDs: [String]
    public var helperCellIDs: [String]
    public var assumptions: [String]

    public init(
        snapshot: LogicDesignSnapshot,
        transformedCellIDs: [String],
        helperCellIDs: [String],
        assumptions: [String]
    ) {
        self.snapshot = snapshot
        self.transformedCellIDs = transformedCellIDs
        self.helperCellIDs = helperCellIDs
        self.assumptions = assumptions
    }
}
