import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public enum DFTArtifactDataLoader {
    public static func load(
        reference: ArtifactReference,
        binding: DFTArtifactBinding,
        reader: any DFTArtifactReading
    ) async throws -> Data {
        guard binding.reference == reference else {
            throw DFTArtifactBindingError.availabilityIdentityMismatch
        }
        let data = try await reader.data(for: binding)
        guard UInt64(data.count) == reference.byteCount else {
            throw DFTArtifactStoreError.readFailed(
                "artifact \(binding.logicalID) returned an invalid byte count"
            )
        }
        let digest = try SHA256ContentDigester().digest(
            data: data,
            using: reference.digest.algorithm
        )
        guard digest == reference.digest else {
            throw DFTArtifactStoreError.readFailed(
                "artifact \(binding.logicalID) returned bytes with a different digest"
            )
        }
        return data
    }
}
