import CircuiteFoundation
import DFTCore

public struct DFTScanPatternReplayResult: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var compiler: DFTExternalToolDescriptor
    public var simulator: DFTExternalToolDescriptor
    public var scanImplementationDigest: String
    public var faultUniverseDigest: String
    public var inputs: [ArtifactReference]
    public var observations: [DFTScanPatternReplayObservation]
    public var artifacts: [ArtifactReference]

    public init(
        runID: String,
        compiler: DFTExternalToolDescriptor,
        simulator: DFTExternalToolDescriptor,
        scanImplementationDigest: String,
        faultUniverseDigest: String,
        inputs: [ArtifactReference],
        observations: [DFTScanPatternReplayObservation],
        artifacts: [ArtifactReference]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.runID = runID
        self.compiler = compiler
        self.simulator = simulator
        self.scanImplementationDigest = scanImplementationDigest
        self.faultUniverseDigest = faultUniverseDigest
        self.inputs = inputs
        self.observations = observations
        self.artifacts = artifacts
    }
}
