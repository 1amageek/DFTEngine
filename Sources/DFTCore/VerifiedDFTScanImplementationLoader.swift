import CircuiteFoundation
import Foundation

public struct VerifiedDFTScanImplementationLoader: DFTScanImplementationLoading {
    public let artifactReader: any DFTArtifactReading

    public init(artifactReader: any DFTArtifactReading) {
        self.artifactReader = artifactReader
    }

    public func load(
        _ reference: DFTScanImplementationReference
    ) async throws -> DFTScanImplementation {
        guard reference.artifact.format == .json else {
            throw DFTScanImplementationLoaderError.unsupportedFormat(
                reference.artifact.format
            )
        }
        let data = try await artifactReader.data(for: reference.artifact)
        let actualByteCount = UInt64(data.count)
        guard actualByteCount == reference.artifact.byteCount else {
            throw DFTScanImplementationLoaderError.byteCountMismatch(
                path: reference.artifact.path,
                expected: reference.artifact.byteCount,
                actual: actualByteCount
            )
        }
        let actualDigest = try SHA256ContentDigester().digest(data: data)
        guard actualDigest == reference.artifact.digest else {
            throw DFTScanImplementationLoaderError.artifactDigestMismatch(
                path: reference.artifact.path,
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
                path: reference.artifact.path,
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
