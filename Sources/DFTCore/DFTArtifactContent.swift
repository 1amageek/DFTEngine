import Foundation

public struct DFTArtifactContent: Sendable, Hashable {
    public var artifactID: String
    public var fileName: String
    public var kind: ArtifactKind
    public var format: ArtifactFormat
    public var data: Data

    public init(
        artifactID: String,
        fileName: String,
        kind: ArtifactKind,
        format: ArtifactFormat,
        data: Data
    ) {
        self.artifactID = artifactID
        self.fileName = fileName
        self.kind = kind
        self.format = format
        self.data = data
    }
}
