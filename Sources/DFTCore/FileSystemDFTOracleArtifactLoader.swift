import Foundation
import CircuiteFoundation
import CircuiteFoundationCrypto

public actor FileSystemDFTOracleArtifactLoader: DFTOracleArtifactLoading {
    public let artifactReader: any DFTArtifactReading

    public init(artifactReader: any DFTArtifactReading) {
        self.artifactReader = artifactReader
    }

    public func load(_ binding: DFTArtifactBinding) async throws -> Data {
        do {
            return try await DFTArtifactDataLoader.load(
                reference: binding.reference,
                binding: binding,
                reader: artifactReader
            )
        } catch {
            throw DFTOracleArtifactError.readFailed(
                path: binding.materializationDescription,
                message: error.localizedDescription
            )
        }
    }
}
