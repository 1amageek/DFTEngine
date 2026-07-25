import CircuiteFoundation
import Foundation

public enum DFTArtifactBatch {
    public static func batchID(
        for contents: [DFTArtifactContent]
    ) throws -> String {
        let identities = contents.map {
            "\($0.artifactID):\($0.fileName)"
        }.sorted().joined(separator: "\n")
        let digest = try SHA256ContentDigester().digest(data: Data(identities.utf8))
        return "batch-\(digest.hexadecimalValue)"
    }

    public static func references(
        for contents: [DFTArtifactContent],
        runID: String
    ) throws -> [ArtifactReference] {
        let batchID = try batchID(for: contents)
        return try contents.map { content in
            ArtifactReference(
                id: try ArtifactID(rawValue: content.artifactID),
                locator: ArtifactLocator(
                    location: try ArtifactLocation(
                        workspaceRelativePath:
                            "dft/runs/\(runID)/\(batchID)/\(content.fileName)"
                    ),
                    role: .output,
                    kind: content.kind,
                    format: content.format
                ),
                digest: try SHA256ContentDigester().digest(data: content.data),
                byteCount: UInt64(content.data.count)
            )
        }
    }
}
