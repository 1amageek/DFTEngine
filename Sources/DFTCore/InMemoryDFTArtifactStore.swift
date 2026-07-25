import Foundation
import CircuiteFoundation

public actor InMemoryDFTArtifactStore: DFTArtifactStoring, DFTArtifactReading {
    private var contents: [String: DFTArtifactContent] = [:]

    public init() {}

    public func store(
        _ content: DFTArtifactContent,
        runID: String
    ) async throws -> ArtifactReference {
        try Self.validate(runID: runID, content: content)
        let path = "dft/runs/\(runID)/\(content.fileName)"
        if let existing = contents[path], existing != content {
            throw DFTArtifactStoreError.artifactConflict(path)
        }
        contents[path] = content
        let digest = try SHA256ContentDigester().digest(data: content.data)
        return ArtifactReference(
            id: try ArtifactID(rawValue: content.artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: path),
                role: .output,
                kind: content.kind,
                format: content.format
            ),
            digest: digest,
            byteCount: UInt64(content.data.count)
        )
    }

    public func storeBatch(
        _ contents: [DFTArtifactContent],
        runID: String
    ) async throws -> [ArtifactReference] {
        guard !contents.isEmpty else { return [] }
        for content in contents {
            try Self.validate(runID: runID, content: content)
        }
        let fileNames = contents.map(\.fileName)
        let artifactIDs = contents.map(\.artifactID)
        guard Set(fileNames).count == fileNames.count,
              Set(artifactIDs).count == artifactIDs.count else {
            throw DFTArtifactStoreError.artifactConflict(
                "dft/runs/\(runID)/<duplicate-batch-identity>"
            )
        }
        let batchID = try DFTArtifactBatch.batchID(for: contents)
        let references = try DFTArtifactBatch.references(
            for: contents,
            runID: runID
        )
        for content in contents {
            let path = "dft/runs/\(runID)/\(batchID)/\(content.fileName)"
            if let existing = self.contents[path], existing != content {
                throw DFTArtifactStoreError.artifactConflict(path)
            }
        }
        for content in contents {
            self.contents[
                "dft/runs/\(runID)/\(batchID)/\(content.fileName)"
            ] = content
        }
        return references
    }

    public func data(for path: String) -> Data? {
        contents[path]?.data
    }

    public func data(for reference: ArtifactReference) async throws -> Data {
        guard let data = contents[reference.path]?.data else {
            throw DFTArtifactStoreError.artifactMissing(reference.path)
        }
        return data
    }

    private static func validate(
        runID: String,
        content: DFTArtifactContent
    ) throws {
        guard isSafeComponent(runID) else {
            throw DFTArtifactStoreError.invalidRunID(runID)
        }
        guard isSafeComponent(content.fileName) else {
            throw DFTArtifactStoreError.invalidFileName(content.fileName)
        }
        do {
            _ = try ArtifactID(rawValue: content.artifactID)
        } catch {
            throw DFTArtifactStoreError.invalidArtifactID(content.artifactID)
        }
    }

    private static func isSafeComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

}
