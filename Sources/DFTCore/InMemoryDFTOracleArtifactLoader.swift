import Foundation
import CircuiteFoundation
import CircuiteFoundationCrypto

public actor InMemoryDFTOracleArtifactLoader: DFTOracleArtifactLoading {
    private let artifacts: [ArtifactID: Data]

    public init(artifacts: [ArtifactID: Data]) {
        self.artifacts = artifacts
    }

    public func load(_ binding: DFTArtifactBinding) async throws -> Data {
        let reference = binding.reference
        guard let data = artifacts[reference.id] else {
            throw DFTOracleArtifactError.readFailed(
                path: binding.materializationDescription,
                message: "artifact is not present in the in-memory corpus"
            )
        }
        let expectedByteCount = reference.byteCount
        if expectedByteCount != UInt64(data.count) {
            throw DFTOracleArtifactError.byteCountMismatch(
                path: binding.materializationDescription,
                expected: Int64(expectedByteCount),
                actual: Int64(data.count)
            )
        }
        let expectedDigest = reference.digest.hexadecimalValue
        let actualDigest = try SHA256ContentDigester().digest(data: data).hexadecimalValue
        guard expectedDigest.caseInsensitiveCompare(actualDigest) == .orderedSame else {
            throw DFTOracleArtifactError.digestMismatch(
                path: binding.materializationDescription,
                expected: expectedDigest,
                actual: actualDigest
            )
        }
        return data
    }

}
