import CircuiteFoundation
import Foundation
import LogicIR
import TimingCore
import PDKCore

public struct DFTRequest: DFTExecutionRequest {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [ArtifactReference]

    public var design: LogicDesignReference
    public var constraints: DFTConstraintReference
    public var pdk: PDKReference
    public var cellLibrary: DFTCellLibraryReference?

    public var operation: DFTOperation
    public var testIntent: DFTTestIntent?
    public var scanArchitecture: DFTScanArchitecture?
    public var insertionPolicy: DFTScanInsertionPolicy?
    public var faultUniverse: DFTFaultUniverse?
    public var atpgConfiguration: DFTATPGConfiguration?
    public var bistConfiguration: DFTBISTConfiguration?

    public init(
        runID: String,
        inputs: [ArtifactReference],
        design: LogicDesignReference,
        constraints: DFTConstraintReference,
        pdk: PDKReference,
        cellLibrary: DFTCellLibraryReference? = nil,
        operation: DFTOperation,
        testIntent: DFTTestIntent? = nil,
        scanArchitecture: DFTScanArchitecture? = nil,
        insertionPolicy: DFTScanInsertionPolicy? = nil,
        faultUniverse: DFTFaultUniverse? = nil,
        atpgConfiguration: DFTATPGConfiguration? = nil,
        bistConfiguration: DFTBISTConfiguration? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.inputs = inputs
        self.design = design
        self.constraints = constraints
        self.pdk = pdk
        self.cellLibrary = cellLibrary
        self.operation = operation
        self.testIntent = testIntent
        self.scanArchitecture = scanArchitecture
        self.insertionPolicy = insertionPolicy
        self.faultUniverse = faultUniverse
        self.atpgConfiguration = atpgConfiguration
        self.bistConfiguration = bistConfiguration
    }

    public var executionInputArtifacts: [ArtifactReference] {
        var references = inputs + [design.artifact, constraints.artifact, pdk.manifest]
        if let cellLibrary {
            references.append(cellLibrary.artifact)
        }
        var identities = Set<ArtifactReference>()
        return references.filter { identities.insert($0).inserted }
    }
}
