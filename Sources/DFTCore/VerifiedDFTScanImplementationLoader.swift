import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation

public struct VerifiedDFTScanImplementationLoader: DFTScanImplementationLoading {
    public let artifactReader: any DFTArtifactReading

    public init(artifactReader: any DFTArtifactReading) {
        self.artifactReader = artifactReader
    }

    public func load(
        _ reference: DFTScanImplementationReference,
        binding: DFTArtifactBinding
    ) async throws -> DFTScanImplementation {
        guard reference.artifact.descriptor.format == .json else {
            throw DFTScanImplementationLoaderError.unsupportedFormat(
                reference.artifact.descriptor.format
            )
        }
        let data = try await DFTArtifactDataLoader.load(
            reference: reference.artifact,
            binding: binding,
            reader: artifactReader
        )
        let actualByteCount = UInt64(data.count)
        guard actualByteCount == reference.artifact.byteCount else {
            throw DFTScanImplementationLoaderError.byteCountMismatch(
                path: binding.materializationDescription,
                expected: reference.artifact.byteCount,
                actual: actualByteCount
            )
        }
        let actualDigest = try SHA256ContentDigester().digest(data: data)
        guard actualDigest == reference.artifact.digest else {
            throw DFTScanImplementationLoaderError.artifactDigestMismatch(
                path: binding.materializationDescription,
                expected: reference.artifact.digest.hexadecimalValue,
                actual: actualDigest.hexadecimalValue
            )
        }
        let implementation: DFTScanImplementation
        do {
            implementation = try JSONDecoder().decode(
                DFTScanImplementation.self,
                from: data
            )
        } catch {
            throw DFTScanImplementationLoaderError.decodeFailed(
                path: binding.materializationDescription,
                message: error.localizedDescription
            )
        }
        guard implementation.transformedDesignDigest
                == reference.transformedDesignDigest else {
            throw DFTScanImplementationLoaderError
                .transformedDesignDigestMismatch(
                    expected: reference.transformedDesignDigest,
                    actual: implementation.transformedDesignDigest
                )
        }
        return implementation
    }
}
