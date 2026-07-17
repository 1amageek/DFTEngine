import CircuiteFoundation
import Foundation

public struct FileSystemDFTCellLibraryLoader: DFTCellLibraryLoading {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func load(_ reference: DFTCellLibraryReference) throws -> DFTCellLibraryManifest {
        guard reference.artifact.format == .json else {
            throw DFTCellLibraryError.unsupportedFormat(reference.artifact.format)
        }
        let url = try resolve(reference.artifact.path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DFTCellLibraryError.readFailed(
                path: reference.artifact.path,
                message: error.localizedDescription
            )
        }
        if reference.artifact.byteCount != UInt64(data.count) {
            throw DFTCellLibraryError.byteCountMismatch(
                path: reference.artifact.path,
                expected: Int64(reference.artifact.byteCount),
                actual: Int64(data.count)
            )
        }
        let expected = reference.artifact.digest.hexadecimalValue
        let actual = try SHA256ContentDigester().digest(data: data).hexadecimalValue
        guard actual == expected else {
            throw DFTCellLibraryError.artifactDigestMismatch(
                path: reference.artifact.path,
                expected: expected,
                actual: actual
            )
        }
        let manifest: DFTCellLibraryManifest
        do {
            manifest = try DFTCellLibraryManifestCodec.decode(data)
        } catch {
            throw DFTCellLibraryError.manifestDecodeFailed(
                path: reference.artifact.path,
                message: error.localizedDescription
            )
        }
        try validate(manifest, reference: reference)
        return manifest
    }

    private func resolve(_ path: String) throws -> URL {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.split(separator: "/").contains("..") else {
            throw DFTCellLibraryError.invalidPath(path)
        }
        let url = rootURL.appendingPathComponent(path).standardizedFileURL
        guard url.path == rootURL.path || url.path.hasPrefix(rootURL.path + "/") else {
            throw DFTCellLibraryError.invalidPath(path)
        }
        return url
    }

    private func validate(
        _ manifest: DFTCellLibraryManifest,
        reference: DFTCellLibraryReference
    ) throws {
        try DFTCellLibraryManifestCodec.validate(manifest)
        let actualDigest = try DFTCellLibraryManifestCodec.digest(manifest)
        guard actualDigest == reference.manifestDigest else {
            throw DFTCellLibraryError.manifestDigestMismatch(
                expected: reference.manifestDigest,
                actual: actualDigest
            )
        }
        guard manifest.processID == reference.processID else {
            throw DFTCellLibraryError.referenceMismatch(
                field: "processID",
                expected: reference.processID,
                actual: manifest.processID
            )
        }
        guard manifest.version == reference.version else {
            throw DFTCellLibraryError.referenceMismatch(
                field: "version",
                expected: reference.version,
                actual: manifest.version
            )
        }
    }
}
