import Foundation

public struct DFTConstraintReference: Sendable, Hashable, Codable {
    public var artifact: DFTArtifactReference
    public var modeIDs: [String]

    public init(artifact: DFTArtifactReference, modeIDs: [String]) {
        self.artifact = artifact
        self.modeIDs = modeIDs
    }
}
