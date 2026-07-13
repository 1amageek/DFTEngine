import Foundation
import XcircuitePackage

public struct DFTCellLibraryReference: Sendable, Hashable, Codable {
    public var artifact: XcircuiteFileReference
    public var processID: String
    public var version: String
    public var manifestDigest: String

    public init(
        artifact: XcircuiteFileReference,
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
