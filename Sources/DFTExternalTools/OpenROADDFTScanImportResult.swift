import CircuiteFoundation
import DFTCore
import LogicIR

public struct OpenROADDFTScanImportResult: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var producer: DFTExternalToolDescriptor
    public var processID: String
    public var pdkDigest: String
    public var inputs: [ArtifactReference]
    public var sourceDesign: LogicDesignReference
    public var transformedDesign: LogicDesignReference
    public var scanImplementation: DFTScanImplementationReference
    public var artifacts: [ArtifactReference]

    public init(
        runID: String,
        producer: DFTExternalToolDescriptor,
        processID: String,
        pdkDigest: String,
        inputs: [ArtifactReference],
        sourceDesign: LogicDesignReference,
        transformedDesign: LogicDesignReference,
        scanImplementation: DFTScanImplementationReference,
        artifacts: [ArtifactReference]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.producer = producer
        self.processID = processID
        self.pdkDigest = pdkDigest
        self.inputs = inputs
        self.sourceDesign = sourceDesign
        self.transformedDesign = transformedDesign
        self.scanImplementation = scanImplementation
        self.artifacts = artifacts
    }
}
