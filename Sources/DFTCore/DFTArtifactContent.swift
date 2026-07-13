import Foundation
import XcircuitePackage

public struct DFTArtifactContent: Sendable, Hashable {
    public var artifactID: String
    public var fileName: String
    public var kind: XcircuiteFileKind
    public var format: XcircuiteFileFormat
    public var data: Data

    public init(
        artifactID: String,
        fileName: String,
        kind: XcircuiteFileKind,
        format: XcircuiteFileFormat,
        data: Data
    ) {
        self.artifactID = artifactID
        self.fileName = fileName
        self.kind = kind
        self.format = format
        self.data = data
    }
}
