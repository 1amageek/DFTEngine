import CircuiteFoundation
import Foundation

public struct DFTConstraintReference: Sendable, Hashable, Codable {
    public var artifact: ArtifactReference
    public var modeIDs: [String]

    public init(artifact: ArtifactReference, modeIDs: [String]) {
        self.artifact = artifact
        self.modeIDs = modeIDs
    }
}
