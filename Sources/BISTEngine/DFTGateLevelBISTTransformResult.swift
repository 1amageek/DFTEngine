import DFTCore
import LogicIR

public struct DFTGateLevelBISTTransformResult: Sendable, Hashable {
    public var snapshot: LogicDesignSnapshot
    public var transformedTargetInstances: [String]
    public var generatedCellIDs: [String]
    public var generatedNetNames: [String]

    public init(
        snapshot: LogicDesignSnapshot,
        transformedTargetInstances: [String],
        generatedCellIDs: [String],
        generatedNetNames: [String]
    ) {
        self.snapshot = snapshot
        self.transformedTargetInstances = transformedTargetInstances
        self.generatedCellIDs = generatedCellIDs
        self.generatedNetNames = generatedNetNames
    }
}
