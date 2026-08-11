import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public struct FileSystemDFTMemoryBISTCellMappingLoader: DFTMemoryBISTCellMappingLoading {
    public let artifactReader: any DFTArtifactReading

    public init(artifactReader: any DFTArtifactReading) {
        self.artifactReader = artifactReader
    }

    public func load(
        _ mapping: DFTMemoryBISTCellMapping,
        binding: DFTArtifactBinding
    ) async throws -> DFTMemoryBISTCellMappingManifest {
        let path = binding.materializationDescription
        guard mapping.artifact.descriptor.format == .json else {
            throw DFTMemoryBISTCellMappingError.invalidPath(path)
        }
        let data: Data
        do {
            data = try await DFTArtifactDataLoader.load(
                reference: mapping.artifact,
                binding: binding,
                reader: artifactReader
            )
        } catch {
            throw DFTMemoryBISTCellMappingError.readFailed(error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(
                DFTMemoryBISTCellMappingManifest.self,
                from: data
            )
        } catch {
            throw DFTMemoryBISTCellMappingError.decodeFailed(error.localizedDescription)
        }
    }
}
