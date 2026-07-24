import CircuiteFoundation
import Foundation

public struct DFTConstraintModeReference: Sendable, Hashable, Codable {
    public var modeID: String
    public var artifact: ArtifactReference

    public init(modeID: String, artifact: ArtifactReference) {
        self.modeID = modeID
        self.artifact = artifact
    }
}
