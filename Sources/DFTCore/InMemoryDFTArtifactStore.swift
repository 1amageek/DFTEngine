import Foundation
import CircuiteFoundation
import CircuiteFoundationCrypto

public actor InMemoryDFTArtifactStore: DFTArtifactStoring, DFTArtifactReading {
    public nonisolated let rootID: ArtifactRootID
    private var contents: [ArtifactID: Data] = [:]
    private var materializations: [String: ArtifactReference] = [:]

    public init() {
        do {
            self.rootID = try ArtifactRootID(rawValue: "dft-memory")
        } catch {
            preconditionFailure("The static DFT in-memory root ID is invalid: \(error)")
        }
    }

    public func store(
        _ content: DFTArtifactContent,
        runID: String
    ) async throws -> DFTArtifactBinding {
        try Self.validate(runID: runID, content: content)
        let path = "dft/runs/\(runID)/\(content.fileName)"
        let digest = try SHA256ContentDigester().digest(data: content.data)
        let reference = try ArtifactReference(
            digest: digest,
            byteCount: UInt64(content.data.count),
            descriptor: ArtifactDescriptor(
                role: .output,
                kind: content.kind,
                format: content.format
            )
        )
        if let existingReference = materializations[path],
           existingReference != reference {
            throw DFTArtifactStoreError.artifactConflict(path)
        }
        if let existing = contents[reference.id], existing != content.data {
            throw DFTArtifactStoreError.artifactConflict(path)
        }
        contents[reference.id] = content.data
        materializations[path] = reference
        return try DFTArtifactBinding(
            logicalID: content.artifactID,
            reference: reference,
            availability: .local(
                artifactID: reference.id,
                rootID: rootID,
                relativePath: ArtifactRelativePath(
                    segments: ["dft", "runs", runID, content.fileName]
                )
            )
        )
    }

    public func storeBatch(
        _ contents: [DFTArtifactContent],
        runID: String
    ) async throws -> [DFTArtifactBinding] {
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
        let bindings = try DFTArtifactBatch.bindings(
            for: contents,
            runID: runID,
            rootID: rootID
        )
        let publications = try zip(contents, bindings).map { content, binding in
            (
                content: content,
                binding: binding,
                path: try binding.requireLocalRelativePath().stringValue
            )
        }
        for publication in publications {
            let content = publication.content
            let binding = publication.binding
            let path = publication.path
            if let existingReference = materializations[path],
               existingReference != binding.reference {
                throw DFTArtifactStoreError.artifactConflict(path)
            }
            if let existing = self.contents[binding.reference.id],
               existing != content.data {
                throw DFTArtifactStoreError.artifactConflict(path)
            }
        }
        for publication in publications {
            self.contents[publication.binding.reference.id] = publication.content.data
            materializations[publication.path] = publication.binding.reference
        }
        return bindings
    }

    public func data(for binding: DFTArtifactBinding) async throws -> Data {
        guard let data = contents[binding.reference.id] else {
            throw DFTArtifactStoreError.artifactMissing(binding.materializationDescription)
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
        guard isSafeComponent(content.artifactID) else {
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
