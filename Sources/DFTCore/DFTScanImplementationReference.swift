import CircuiteFoundation
import Foundation

public struct DFTScanImplementationReference: Sendable, Hashable, Codable {
    public var artifact: ArtifactReference
    public var transformedDesignDigest: String

    public init(
        artifact: ArtifactReference,
        transformedDesignDigest: String
    ) {
        self.artifact = artifact
        self.transformedDesignDigest = transformedDesignDigest
    }
}
