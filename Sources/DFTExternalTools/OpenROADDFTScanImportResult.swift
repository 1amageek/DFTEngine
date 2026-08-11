import CircuiteFoundation
import DFTCore
import LogicIR

public struct OpenROADDFTScanImportResult: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var runID: String
    public var producer: DFTExternalToolDescriptor
    public var processID: String
    public var pdkDigest: String
    public var inputBindings: [DFTArtifactBinding]
    public var sourceDesign: LogicDesignReference
    public var transformedDesign: LogicDesignReference
    public var scanImplementation: DFTScanImplementationReference
    public var artifactBindings: [DFTArtifactBinding]

    public var inputs: [ArtifactReference] { inputBindings.map(\.reference) }
    public var artifacts: [ArtifactReference] { artifactBindings.map(\.reference) }

    public init(
        runID: String,
        producer: DFTExternalToolDescriptor,
        processID: String,
        pdkDigest: String,
        inputBindings: [DFTArtifactBinding],
        sourceDesign: LogicDesignReference,
        transformedDesign: LogicDesignReference,
        scanImplementation: DFTScanImplementationReference,
        artifactBindings: [DFTArtifactBinding]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.producer = producer
        self.processID = processID
        self.pdkDigest = pdkDigest
        self.inputBindings = inputBindings
        self.sourceDesign = sourceDesign
        self.transformedDesign = transformedDesign
        self.scanImplementation = scanImplementation
        self.artifactBindings = artifactBindings
    }

    public func requireBinding(
        for reference: ArtifactReference
    ) throws -> DFTArtifactBinding {
        try DFTArtifactBinding.require(
            reference,
            in: inputBindings + artifactBindings
        )
    }
}
