import DFTCore
import LogicIR

public struct DFTGateLevelScanTransformResult: Sendable, Hashable {
    public var snapshot: LogicDesignSnapshot
    public var transformedCellIDs: [String]
    public var helperCellIDs: [String]
    public var scanImplementation: DFTScanImplementation
    public var assumptions: [String]

    public init(
        snapshot: LogicDesignSnapshot,
        transformedCellIDs: [String],
        helperCellIDs: [String],
        scanImplementation: DFTScanImplementation,
        assumptions: [String]
    ) {
        self.snapshot = snapshot
        self.transformedCellIDs = transformedCellIDs
        self.helperCellIDs = helperCellIDs
        self.scanImplementation = scanImplementation
        self.assumptions = assumptions
    }
}
