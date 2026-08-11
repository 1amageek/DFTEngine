import CircuiteFoundation
import DFTCore

public struct DFTScanPatternReplayResult: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var runID: String
    public var compiler: DFTExternalToolDescriptor
    public var simulator: DFTExternalToolDescriptor
    public var scanImplementationDigest: String
    public var faultUniverseDigest: String
    public var inputBindings: [DFTArtifactBinding]
    public var observations: [DFTScanPatternReplayObservation]
    public var artifactBindings: [DFTArtifactBinding]

    public var inputs: [ArtifactReference] { inputBindings.map(\.reference) }
    public var artifacts: [ArtifactReference] { artifactBindings.map(\.reference) }

    public init(
        runID: String,
        compiler: DFTExternalToolDescriptor,
        simulator: DFTExternalToolDescriptor,
        scanImplementationDigest: String,
        faultUniverseDigest: String,
        inputBindings: [DFTArtifactBinding],
        observations: [DFTScanPatternReplayObservation],
        artifactBindings: [DFTArtifactBinding]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.compiler = compiler
        self.simulator = simulator
        self.scanImplementationDigest = scanImplementationDigest
        self.faultUniverseDigest = faultUniverseDigest
        self.inputBindings = inputBindings
        self.observations = observations
        self.artifactBindings = artifactBindings
    }
}
