import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public struct FileSystemDFTLogicBISTCellMappingLoader: DFTLogicBISTCellMappingLoading {
    public let artifactReader: any DFTArtifactReading

    public init(artifactReader: any DFTArtifactReading) {
        self.artifactReader = artifactReader
    }

    public func load(
        _ mapping: DFTLogicBISTCellMapping,
        binding: DFTArtifactBinding
    ) async throws -> DFTLogicBISTCellMappingManifest {
        let path = binding.materializationDescription
        guard mapping.artifact.descriptor.format == .json else {
            throw DFTLogicBISTCellMappingError.invalidPath(path)
        }
        let data: Data
        do {
            data = try await DFTArtifactDataLoader.load(
                reference: mapping.artifact,
                binding: binding,
                reader: artifactReader
            )
        } catch {
            throw DFTLogicBISTCellMappingError.readFailed(error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(
                DFTLogicBISTCellMappingManifest.self,
                from: data
            )
        } catch {
            throw DFTLogicBISTCellMappingError.decodeFailed(error.localizedDescription)
        }
    }
}
