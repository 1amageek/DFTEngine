import CircuiteFoundation
import Foundation
import LogicIR
import TimingCore
import PDKCore

public struct DFTRequest: DFTExecutionRequest {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var runID: String
    public var inputs: [ArtifactReference]
    public var inputBindings: [DFTArtifactBinding]

    public var design: LogicDesignReference
    public var constraints: DFTConstraintReference
    public var pdk: PDKReference
    public var cellLibrary: DFTCellLibraryReference?
    public var scanImplementation: DFTScanImplementationReference?

    public var operation: DFTOperation
    public var testIntent: DFTTestIntent?
    public var scanArchitecture: DFTScanArchitecture?
    public var insertionPolicy: DFTScanInsertionPolicy?
    public var faultUniverse: DFTFaultUniverse?
    public var atpgConfiguration: DFTATPGConfiguration?
    public var bistConfiguration: DFTBISTConfiguration?

    public init(
        runID: String,
        inputBindings: [DFTArtifactBinding],
        design: LogicDesignReference,
        constraints: DFTConstraintReference,
        pdk: PDKReference,
        cellLibrary: DFTCellLibraryReference? = nil,
        scanImplementation: DFTScanImplementationReference? = nil,
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
        self.inputBindings = inputBindings
        self.design = design
        self.constraints = constraints
        self.pdk = pdk
        self.cellLibrary = cellLibrary
        self.scanImplementation = scanImplementation
        self.operation = operation
        self.testIntent = testIntent
        self.scanArchitecture = scanArchitecture
        self.insertionPolicy = insertionPolicy
        self.faultUniverse = faultUniverse
        self.atpgConfiguration = atpgConfiguration
        self.bistConfiguration = bistConfiguration
        self.inputs = []
        self.inputs = executionInputArtifacts
    }

    public var executionInputArtifacts: [ArtifactReference] {
        var references = inputBindings.map(\.reference)
            + [design.artifact, pdk.manifest]
            + constraints.artifacts
        if let cellLibrary {
            references.append(cellLibrary.artifact)
            if let timingLibraryArtifact = cellLibrary.timingLibraryArtifact {
                references.append(timingLibraryArtifact)
            }
        }
        if let scanImplementation {
            references.append(scanImplementation.artifact)
        }
        if let logicCellMapping = bistConfiguration?.logicCellMapping {
            references.append(logicCellMapping.artifact)
        }
        if let memoryCellMapping = bistConfiguration?.memoryCellMapping {
            references.append(memoryCellMapping.artifact)
        }
        var identities = Set<ArtifactReference>()
        return references.filter { identities.insert($0).inserted }
    }

    public func requireBinding(
        for reference: ArtifactReference
    ) throws -> DFTArtifactBinding {
        try DFTArtifactBinding.require(reference, in: inputBindings)
    }
}
