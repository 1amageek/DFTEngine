import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public struct FileSystemDFTCellLibraryLoader: DFTCellLibraryLoading {
    public let artifactReader: any DFTArtifactReading

    public init(artifactReader: any DFTArtifactReading) {
        self.artifactReader = artifactReader
    }

    public func load(
        _ reference: DFTCellLibraryReference,
        binding: DFTArtifactBinding
    ) async throws -> DFTCellLibraryManifest {
        guard reference.artifact.descriptor.format == .json else {
            throw DFTCellLibraryError.unsupportedFormat(reference.artifact.descriptor.format)
        }
        let data: Data
        do {
            data = try await DFTArtifactDataLoader.load(
                reference: reference.artifact,
                binding: binding,
                reader: artifactReader
            )
        } catch {
            throw DFTCellLibraryError.readFailed(
                path: binding.materializationDescription,
                message: error.localizedDescription
            )
        }
        let manifest: DFTCellLibraryManifest
        do {
            manifest = try DFTCellLibraryManifestCodec.decode(data)
        } catch {
            throw DFTCellLibraryError.manifestDecodeFailed(
                path: binding.materializationDescription,
                message: error.localizedDescription
            )
        }
        try validate(manifest, reference: reference)
        return manifest
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
