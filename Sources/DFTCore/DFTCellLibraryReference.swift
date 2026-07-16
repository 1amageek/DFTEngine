import CircuiteFoundation
import Foundation

public struct DFTCellLibraryReference: Sendable, Hashable, Codable {
    public var artifact: ArtifactReference
    public var processID: String
    public var version: String
    public var manifestDigest: String

    public init(
        artifact: ArtifactReference,
        processID: String,
        version: String,
        manifestDigest: String
    ) {
        self.artifact = artifact
        self.processID = processID
        self.version = version
        self.manifestDigest = manifestDigest
    }
}
