import Foundation
import CircuiteFoundation

public actor InMemoryDFTOracleArtifactLoader: DFTOracleArtifactLoading {
    private let artifacts: [String: Data]

    public init(artifacts: [String: Data]) {
        self.artifacts = artifacts
    }

    public func load(_ reference: ArtifactReference) async throws -> Data {
        try Self.validate(reference)
        guard let data = artifacts[reference.path] else {
            throw DFTOracleArtifactError.readFailed(
                path: reference.path,
                message: "artifact is not present in the in-memory corpus"
            )
        }
        let expectedByteCount = reference.byteCount
        if expectedByteCount != UInt64(data.count) {
            throw DFTOracleArtifactError.byteCountMismatch(
                path: reference.path,
                expected: Int64(expectedByteCount),
                actual: Int64(data.count)
            )
        }
        let expectedDigest = reference.digest.hexadecimalValue
        let actualDigest = DFTHasher().sha256(data: data)
        guard expectedDigest.caseInsensitiveCompare(actualDigest) == .orderedSame else {
            throw DFTOracleArtifactError.digestMismatch(
                path: reference.path,
                expected: expectedDigest,
                actual: actualDigest
            )
        }
        return data
    }

    private static func validate(_ reference: ArtifactReference) throws {
        let artifactID = reference.artifactID
        do {
            _ = try ArtifactID(rawValue: artifactID)
        } catch {
            throw DFTOracleArtifactError.invalidReference(reference.path)
        }
        guard isSafePath(reference.path) else {
            throw DFTOracleArtifactError.invalidReference(reference.path)
        }
        let digest = reference.digest.hexadecimalValue
        guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else {
            throw DFTOracleArtifactError.invalidDigest(reference.path)
        }
    }

    private static func isSafePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return false
        }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }
}
