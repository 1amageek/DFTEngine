import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public enum DFTArtifactBatch {
    public static func reference(
        for content: DFTArtifactContent
    ) throws -> ArtifactReference {
        try ArtifactReference(
            digest: SHA256ContentDigester().digest(data: content.data),
            byteCount: UInt64(content.data.count),
            descriptor: ArtifactDescriptor(
                role: .output,
                kind: content.kind,
                format: content.format
            )
        )
    }

    public static func batchID(
        for contents: [DFTArtifactContent]
    ) throws -> String {
        let identities = contents.map {
            "\($0.artifactID):\($0.fileName)"
        }.sorted().joined(separator: "\n")
        let digest = try SHA256ContentDigester().digest(data: Data(identities.utf8))
        return "batch-\(digest.hexadecimalValue)"
    }

    public static func bindings(
        for contents: [DFTArtifactContent],
        runID: String,
        rootID: ArtifactRootID
    ) throws -> [DFTArtifactBinding] {
        let batchID = try batchID(for: contents)
        return try contents.map { content in
            let reference = try reference(for: content)
            let relativePath = try ArtifactRelativePath(
                segments: ["dft", "runs", runID, batchID, content.fileName]
            )
            return try DFTArtifactBinding(
                logicalID: content.artifactID,
                reference: reference,
                availability: .local(
                    artifactID: reference.id,
                    rootID: rootID,
                    relativePath: relativePath
                )
            )
        }
    }
}
