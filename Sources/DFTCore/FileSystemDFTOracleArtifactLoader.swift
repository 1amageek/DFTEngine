import Foundation
import CircuiteFoundation

public actor FileSystemDFTOracleArtifactLoader: DFTOracleArtifactLoading {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func load(_ reference: ArtifactReference) async throws -> Data {
        try Self.validate(reference)
        let expectedByteCount = reference.byteCount
        let expectedDigest = reference.digest.hexadecimalValue
        let resolvedURL: URL
        do {
            resolvedURL = try DFTProjectArtifactResolver(
                rootURL: rootURL
            ).resolve(reference.path)
        } catch {
            throw DFTOracleArtifactError.invalidReference(reference.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: resolvedURL, options: .mappedIfSafe)
        } catch {
            throw DFTOracleArtifactError.readFailed(
                path: reference.path,
                message: error.localizedDescription
            )
        }
        if expectedByteCount != UInt64(data.count) {
            throw DFTOracleArtifactError.byteCountMismatch(
                path: reference.path,
                expected: Int64(expectedByteCount),
                actual: Int64(data.count)
            )
        }
        let actualDigest = try SHA256ContentDigester().digest(data: data).hexadecimalValue
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
        guard reference.digest.algorithm == .sha256,
              isSHA256(reference.digest.hexadecimalValue) else {
            throw DFTOracleArtifactError.invalidDigest(reference.path)
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
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
