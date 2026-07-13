import Foundation
import CircuiteFoundation
import XcircuitePackage

public actor InMemoryDFTArtifactStore: DFTArtifactStoring {
    private var contents: [String: DFTArtifactContent] = [:]

    public init() {}

    public func store(
        _ content: DFTArtifactContent,
        runID: String
    ) async throws -> XcircuiteFileReference {
        try Self.validate(runID: runID, content: content)
        let path = "dft/runs/\(runID)/\(content.fileName)"
        if let existing = contents[path], existing != content {
            throw DFTArtifactStoreError.artifactConflict(path)
        }
        contents[path] = content
        return XcircuiteFileReference(
            artifactID: content.artifactID,
            path: path,
            kind: content.kind,
            format: content.format,
            sha256: XcircuiteHasher().sha256(data: content.data),
            byteCount: Int64(content.data.count),
            producedByRunID: runID
        )
    }

    public func data(for path: String) -> Data? {
        contents[path]?.data
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
