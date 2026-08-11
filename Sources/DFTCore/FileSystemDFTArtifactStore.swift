import Foundation
import CircuiteFoundation
import CircuiteFoundationCrypto
import CircuiteFoundationFileSystem

public actor FileSystemDFTArtifactStore: DFTArtifactStoring, DFTArtifactReading {
    public nonisolated let rootURL: URL
    public nonisolated let rootID: ArtifactRootID

    private let artifactAccess: ArtifactRootCapability
    private let readBudget: ArtifactAccessBudget

    public init(rootURL: URL) throws {
        try self.init(
            rootURL: rootURL,
            rootID: ArtifactRootID(rawValue: "dft-project")
        )
    }

    public init(rootURL: URL, rootID: ArtifactRootID) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.rootID = rootID
        self.artifactAccess = try ArtifactRootCapability(
            rootID: rootID,
            directoryURL: rootURL,
            digester: SHA256ContentDigester()
        )
        self.readBudget = try ArtifactAccessBudget(
            maximumPageByteCount: 1_048_576,
            maximumTotalByteCount: 1_073_741_824,
            maximumPageCount: 1_024,
            maximumWorkUnitCount: 4_096,
            maximumDurationNanoseconds: 60_000_000_000
        )
    }

    public func store(
        _ content: DFTArtifactContent,
        runID: String
    ) async throws -> DFTArtifactBinding {
        try Self.validate(runID: runID, content: content)
        let directory = rootURL
            .appending(path: "dft")
            .appending(path: "runs")
            .appending(path: runID)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw DFTArtifactStoreError.directoryCreationFailed(error.localizedDescription)
        }
        let destination = directory.appending(path: content.fileName)
        let resolvedRoot = rootURL.resolvingSymlinksInPath()
        let resolvedDirectory = directory.resolvingSymlinksInPath()
        let resolvedDestination = destination.resolvingSymlinksInPath()
        guard Self.isInside(resolvedDirectory, root: resolvedRoot),
              Self.isInside(resolvedDestination, root: resolvedRoot) else {
            throw DFTArtifactStoreError.pathOutsideRoot(
                "dft/runs/\(runID)/\(content.fileName)"
            )
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            let existingData: Data
            do {
                existingData = try Data(contentsOf: destination)
            } catch {
                throw DFTArtifactStoreError.writeFailed(error.localizedDescription)
            }
            guard existingData == content.data else {
                throw DFTArtifactStoreError.artifactConflict(
                    "dft/runs/\(runID)/\(content.fileName)"
                )
            }
        } else {
            do {
                try content.data.write(to: destination, options: .atomic)
            } catch {
                throw DFTArtifactStoreError.writeFailed(error.localizedDescription)
            }
        }
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
        let batchID = try DFTArtifactBatch.batchID(for: contents)
        let runDirectory = rootURL
            .appending(path: "dft")
            .appending(path: "runs")
            .appending(path: runID)
        let destination = runDirectory.appending(path: batchID)
        let resolvedRoot = rootURL.resolvingSymlinksInPath()
        guard Self.isInside(runDirectory.resolvingSymlinksInPath(), root: resolvedRoot),
              Self.isInside(destination.resolvingSymlinksInPath(), root: resolvedRoot) else {
            throw DFTArtifactStoreError.pathOutsideRoot(
                "dft/runs/\(runID)/\(batchID)"
            )
        }
        do {
            try FileManager.default.createDirectory(
                at: runDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw DFTArtifactStoreError.directoryCreationFailed(
                error.localizedDescription
            )
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            guard try Self.batchMatches(contents, at: destination) else {
                throw DFTArtifactStoreError.artifactConflict(
                    "dft/runs/\(runID)/\(batchID)"
                )
            }
        } else {
            let staging = runDirectory.appending(
                path: ".staging-\(batchID)-\(UUID().uuidString)"
            )
            do {
                try FileManager.default.createDirectory(
                    at: staging,
                    withIntermediateDirectories: false
                )
                for content in contents {
                    try content.data.write(
                        to: staging.appending(path: content.fileName),
                        options: .atomic
                    )
                }
                try FileManager.default.moveItem(at: staging, to: destination)
            } catch {
                let destinationExists = FileManager.default.fileExists(
                    atPath: destination.path
                )
                let publicationWonByAnotherStore: Bool
                if destinationExists {
                    publicationWonByAnotherStore = try Self.batchMatches(
                        contents,
                        at: destination
                    )
                } else {
                    publicationWonByAnotherStore = false
                }
                if FileManager.default.fileExists(atPath: staging.path) {
                    do {
                        try FileManager.default.removeItem(at: staging)
                    } catch {
                        throw DFTArtifactStoreError.writeFailed(
                            "batch write failed and staging cleanup failed: \(error.localizedDescription)"
                        )
                    }
                }
                if publicationWonByAnotherStore {
                    return try DFTArtifactBatch.bindings(
                        for: contents,
                        runID: runID,
                        rootID: rootID
                    )
                }
                if destinationExists {
                    throw DFTArtifactStoreError.artifactConflict(
                        "dft/runs/\(runID)/\(batchID)"
                    )
                }
                throw DFTArtifactStoreError.writeFailed(
                    error.localizedDescription
                )
            }
        }
        return try DFTArtifactBatch.bindings(
            for: contents,
            runID: runID,
            rootID: rootID
        )
    }

    public func data(for binding: DFTArtifactBinding) async throws -> Data {
        let intent: ArtifactAccessIntent
        do {
            intent = try ArtifactAccessIntent(
                expectedReference: binding.reference,
                availability: binding.availability,
                operation: .read,
                budget: readBudget
            )
        } catch {
            throw DFTArtifactStoreError.readFailed(
                "\(binding.materializationDescription): \(error)"
            )
        }
        let session: any ArtifactReadSession
        do {
            session = try await artifactAccess.open(intent)
        } catch {
            throw DFTArtifactStoreError.readFailed(
                "\(binding.materializationDescription): \(error)"
            )
        }
        do {
            var data = Data()
            var offset: UInt64 = 0
            while true {
                let page = try await session.readPage(
                    ArtifactReadPageRequest(
                        offset: offset,
                        maximumByteCount: readBudget.maximumPageByteCount
                    )
                )
                page.bytes.withUnsafeBytes { bytes in
                    data.append(contentsOf: bytes)
                }
                offset = page.cumulativeByteCount
                if page.completion == .complete {
                    break
                }
            }
            _ = try await session.close().wait()
            return data
        } catch let primaryError {
            do {
                _ = try await session.close().wait()
            } catch let closeError {
                throw DFTArtifactStoreError.readFailed(
                    "read failed: \(primaryError); close failed: \(closeError)"
                )
            }
            throw DFTArtifactStoreError.readFailed(String(describing: primaryError))
        }
    }

    public func shutdown() async throws {
        try await artifactAccess.close().wait()
    }

    private static func isInside(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path == root.path || candidate.path.hasPrefix(rootPath)
    }

    private static func batchMatches(
        _ contents: [DFTArtifactContent],
        at directory: URL
    ) throws -> Bool {
        for content in contents {
            let existing: Data
            do {
                existing = try Data(
                    contentsOf: directory.appending(path: content.fileName),
                    options: .mappedIfSafe
                )
            } catch {
                throw DFTArtifactStoreError.writeFailed(
                    error.localizedDescription
                )
            }
            guard existing == content.data else {
                return false
            }
        }
        return true
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
