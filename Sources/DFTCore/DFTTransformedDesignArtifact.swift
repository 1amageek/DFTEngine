import Foundation
import LogicIR

public struct DFTTransformedDesignArtifact: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var runID: String
    public var operation: DFTOperation
    public var sourceDesign: LogicDesignReference
    public var scanPlan: DFTScanPlan?
    public var bistStructure: DFTBISTStructure?
    public var assumptions: [String]

    public init(
        schemaVersion: Int = 1,
        runID: String,
        operation: DFTOperation,
        sourceDesign: LogicDesignReference,
        scanPlan: DFTScanPlan? = nil,
        bistStructure: DFTBISTStructure? = nil,
        assumptions: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.operation = operation
        self.sourceDesign = sourceDesign
        self.scanPlan = scanPlan
        self.bistStructure = bistStructure
        self.assumptions = assumptions
    }
}
