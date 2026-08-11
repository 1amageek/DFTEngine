import CircuiteFoundation
import DFTCore

public struct DFTScanPatternReplayRequest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var runID: String
    public var topModule: String
    public var patternArtifact: ArtifactReference
    public var scanNetlistArtifact: ArtifactReference
    public var scanImplementation: DFTScanImplementationReference
    public var faultUniverseArtifact: ArtifactReference
    public var cellModelArtifacts: [ArtifactReference]
    public var preprocessorDefines: [String]
    public var faultIDs: [String]
    public var inputBindings: [DFTArtifactBinding]

    public init(
        runID: String,
        topModule: String,
        patternArtifact: ArtifactReference,
        scanNetlistArtifact: ArtifactReference,
        scanImplementation: DFTScanImplementationReference,
        faultUniverseArtifact: ArtifactReference,
        cellModelArtifacts: [ArtifactReference],
        inputBindings: [DFTArtifactBinding],
        preprocessorDefines: [String] = [],
        faultIDs: [String]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.topModule = topModule
        self.patternArtifact = patternArtifact
        self.scanNetlistArtifact = scanNetlistArtifact
        self.scanImplementation = scanImplementation
        self.faultUniverseArtifact = faultUniverseArtifact
        self.cellModelArtifacts = cellModelArtifacts
        self.inputBindings = inputBindings
        self.preprocessorDefines = preprocessorDefines
        self.faultIDs = faultIDs
    }

    public func requireBinding(
        for reference: ArtifactReference
    ) throws -> DFTArtifactBinding {
        try DFTArtifactBinding.require(reference, in: inputBindings)
    }
}
