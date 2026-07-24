import Foundation
import CircuiteFoundation

public actor FileSystemDFTArtifactStore: DFTArtifactStoring, DFTArtifactReading {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func store(
        _ content: DFTArtifactContent,
        runID: String
    ) async throws -> ArtifactReference {
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
        let artifactPath = "dft/runs/\(runID)/\(content.fileName)"
        let digest = try SHA256ContentDigester().digest(data: content.data)
        return ArtifactReference(
            id: try ArtifactID(rawValue: content.artifactID),
            locator: ArtifactLocator(
                location: try ArtifactLocation(workspaceRelativePath: artifactPath),
                role: .output,
                kind: content.kind,
                format: content.format
            ),
            digest: digest,
            byteCount: UInt64(content.data.count)
        )
    }

    public func data(for reference: ArtifactReference) async throws -> Data {
        let path = reference.path
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.split(separator: "/").contains("..") else {
            throw DFTArtifactStoreError.pathOutsideRoot(path)
        }
        let url = rootURL.appendingPathComponent(path).standardizedFileURL
        let resolvedRoot = rootURL.resolvingSymlinksInPath()
        let resolvedURL = url.resolvingSymlinksInPath()
        guard Self.isInside(resolvedURL, root: resolvedRoot) else {
            throw DFTArtifactStoreError.pathOutsideRoot(path)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DFTArtifactStoreError.artifactMissing(path)
        }
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw DFTArtifactStoreError.readFailed(error.localizedDescription)
        }
    }

    private static func isInside(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path == root.path || candidate.path.hasPrefix(rootPath)
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
