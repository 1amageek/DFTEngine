import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation
import TimingCore

public struct FileSystemDFTTimingLibraryLoader: DFTTimingLibraryLoading {
    public let artifactReader: any DFTArtifactReading

    public init(artifactReader: any DFTArtifactReading) {
        self.artifactReader = artifactReader
    }

    public func load(
        _ reference: ArtifactReference,
        binding: DFTArtifactBinding
    ) async throws -> TimingLibrary {
        guard reference.descriptor.format == .liberty
                || reference.descriptor.format == .json else {
            throw DFTCellLibraryError.unsupportedFormat(reference.descriptor.format)
        }
        let data: Data
        do {
            data = try await DFTArtifactDataLoader.load(
                reference: reference,
                binding: binding,
                reader: artifactReader
            )
        } catch {
            throw DFTCellLibraryError.readFailed(
                path: binding.materializationDescription,
                message: error.localizedDescription
            )
        }
        return try LibertyParser().parse(data)
    }
}
