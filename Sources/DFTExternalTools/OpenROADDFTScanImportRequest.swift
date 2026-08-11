import CircuiteFoundation
import DFTCore

public struct OpenROADDFTScanImportRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var runID: String
    public var architectureName: String
    public var topModule: String
    public var scanEnableSignal: String
    public var testModeSignal: String
    public var sourceNetlistArtifact: ArtifactReference
    public var transformedNetlistArtifact: ArtifactReference
    public var scanDEFArtifact: ArtifactReference
    public var cellLibraryArtifact: ArtifactReference
    public var executionEvidenceArtifact: ArtifactReference
    public var inputBindings: [DFTArtifactBinding]
    public var producer: DFTExternalToolDescriptor

    public init(
        runID: String,
        architectureName: String,
        topModule: String,
        scanEnableSignal: String,
        testModeSignal: String,
        sourceNetlistArtifact: ArtifactReference,
        transformedNetlistArtifact: ArtifactReference,
        scanDEFArtifact: ArtifactReference,
        cellLibraryArtifact: ArtifactReference,
        executionEvidenceArtifact: ArtifactReference,
        inputBindings: [DFTArtifactBinding],
        producer: DFTExternalToolDescriptor
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.architectureName = architectureName
        self.topModule = topModule
        self.scanEnableSignal = scanEnableSignal
        self.testModeSignal = testModeSignal
        self.sourceNetlistArtifact = sourceNetlistArtifact
        self.transformedNetlistArtifact = transformedNetlistArtifact
        self.scanDEFArtifact = scanDEFArtifact
        self.cellLibraryArtifact = cellLibraryArtifact
        self.executionEvidenceArtifact = executionEvidenceArtifact
        self.inputBindings = inputBindings
        self.producer = producer
    }

    public func requireBinding(
        for reference: ArtifactReference
    ) throws -> DFTArtifactBinding {
        try DFTArtifactBinding.require(reference, in: inputBindings)
    }
}
